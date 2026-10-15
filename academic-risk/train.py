"""Train and export exactly one shared PyTorch course-risk artifact."""
from __future__ import annotations

import argparse
import copy
from datetime import datetime,timezone
import hashlib
import json
import os
os.environ.setdefault('CUBLAS_WORKSPACE_CONFIG',':4096:8')
os.environ.setdefault('LOKY_MAX_CPU_COUNT','2')
from pathlib import Path
import platform
import sys
import time

import numpy as np
import pandas as pd
import sklearn
from sklearn.ensemble import HistGradientBoostingClassifier
from sklearn.impute import SimpleImputer
from sklearn.linear_model import LogisticRegression
from sklearn.model_selection import GroupShuffleSplit
from sklearn.pipeline import make_pipeline
import torch
from torch import nn

from model import FEATURES,CourseRiskModel,predict_arrays,seed_everything,load_model
from metrics import scores,macro_source_scores,choose_threshold,grouped_report,cluster_bootstrap
from download_data import ROOT,sha256


def write_json(path,value):
    path.write_text(json.dumps(value,indent=2,allow_nan=False),encoding='utf-8')


class Tee:
    def __init__(self,stream,path):self.stream,self.file=stream,path.open('w',encoding='utf-8',buffering=1)
    def write(self,text):self.stream.write(text);self.file.write(text)
    def flush(self):self.stream.flush();self.file.flush()


def assign_splits(frame,seed):
    """Student groups never cross partitions; one whole module is additionally held out."""
    assignments={}
    unseen_groups=set(frame.loc[(frame.source=='oulad')&(frame.subject=='GGG'),'group'])
    for source in frame.source.unique():
        subset=frame[(frame.source==source)&(~frame.group.isin(unseen_groups))]
        indices=subset.index.to_numpy()
        groups=subset.group.to_numpy()
        first=GroupShuffleSplit(n_splits=1,test_size=.20,random_state=seed)
        dev_pos,test_pos=next(first.split(indices,groups=groups))
        development=indices[dev_pos]
        for idx in indices[test_pos]:assignments[int(idx)]='test'
        splitter=GroupShuffleSplit(n_splits=1,test_size=.125,random_state=seed+1)
        trainval_pos,cal_pos=next(splitter.split(development,groups=frame.loc[development,'group']))
        for idx in development[cal_pos]:assignments[int(idx)]='calibration'
        remaining=development[trainval_pos]
        splitter=GroupShuffleSplit(n_splits=1,test_size=1/7,random_state=seed+2)
        train_pos,val_pos=next(splitter.split(remaining,groups=frame.loc[remaining,'group']))
        for idx in remaining[train_pos]:assignments[int(idx)]='train'
        for idx in remaining[val_pos]:assignments[int(idx)]='validation'
    for idx in frame.index[frame.group.isin(unseen_groups)]:assignments[int(idx)]='unseen_subject_test'
    splits=frame.index.map(assignments).to_numpy()
    if pd.isna(splits).any():raise ValueError('Some observations were not assigned to a partition')
    if pd.DataFrame({'group':frame.group,'split':splits}).groupby('group').split.nunique().max()!=1:
        raise ValueError('Student leakage across partitions')
    if (frame.loc[np.isin(splits,['train','validation','calibration']),'subject']=='GGG').any():
        raise ValueError('Held-out course leaked into development data')
    return splits


def source_weights(frame):
    counts=frame.source.value_counts()
    # A large adult dataset must not drown out the much smaller school dataset.
    weights=frame.source.map(lambda s:1/counts[s]).to_numpy(dtype=float)
    return weights/weights.mean()


def train_candidate(train,validation,config,args,device):
    seed_everything(args.seed)
    model=CourseRiskModel(hidden=config['hidden'],dropout=config['dropout'])
    model.fit_preprocessing(train[FEATURES].to_numpy(dtype=np.float32))
    model.to(device)
    xt=torch.tensor(train[FEATURES].to_numpy(dtype=np.float32),device=device)
    yt=torch.tensor(train.target.to_numpy(),dtype=torch.float32,device=device)
    xv=validation[FEATURES].to_numpy(dtype=np.float32)
    optimizer=torch.optim.AdamW(model.parameters(),lr=config['lr'],weight_decay=config['weight_decay'])
    sampling=torch.tensor(source_weights(train),dtype=torch.float64)
    generator=torch.Generator().manual_seed(args.seed)
    best_state,best_loss,best_epoch,stale=None,float('inf'),0,0
    history=[]
    steps=max(1,min(len(train),args.samples_per_epoch)//args.batch_size)
    start=time.monotonic()
    for epoch in range(1,args.epochs+1):
        model.train()
        selected=torch.multinomial(sampling,steps*args.batch_size,replacement=True,generator=generator)
        total_loss,total_correct=0.,0
        for part in selected.split(args.batch_size):
            batch=part.to(device)
            optimizer.zero_grad(set_to_none=True)
            logits=model(xt[batch])
            loss=nn.functional.binary_cross_entropy_with_logits(logits,yt[batch])
            if not torch.isfinite(loss):raise RuntimeError('Non-finite training loss')
            loss.backward()
            nn.utils.clip_grad_norm_(model.parameters(),5.)
            optimizer.step()
            total_loss+=float(loss.detach())*len(part)
            total_correct+=int(((logits.detach()>=0)==yt[batch].bool()).sum())
        p=predict_arrays(model,xv,device,calibrated=False)
        stats=macro_source_scores(validation,p,.5)
        validation_loss=stats['log_loss']
        history.append({'epoch':epoch,'train_loss':total_loss/len(selected),
            'train_accuracy':total_correct/len(selected),'validation_loss':validation_loss,
            'validation_accuracy':stats['accuracy'],'validation_recall':stats['recall']})
        if validation_loss<best_loss-1e-4:
            best_loss,best_epoch,stale=validation_loss,epoch,0
            best_state=copy.deepcopy(model.state_dict())
        else:stale+=1
        if epoch==1 or epoch%10==0:
            print(f"  epoch {epoch:3d} train BCE={history[-1]['train_loss']:.4f} acc={history[-1]['train_accuracy']:.3f} | validation BCE={validation_loss:.4f} macro accuracy={stats['accuracy']:.3f} recall={stats['recall']:.3f}",flush=True)
        if stale>=args.patience:break
    model.load_state_dict(best_state)
    p=predict_arrays(model,xv,device,calibrated=False)
    threshold,_,feasible=choose_threshold(validation,p,args.min_recall)
    stats=macro_source_scores(validation,p,threshold)
    return model,history,{'config':config,'best_epoch':best_epoch,'epochs':epoch,'seconds':time.monotonic()-start,
        'validation':stats,'validation_threshold':threshold,'recall_constraint_met':feasible}


def run(args):
    path=ROOT/'data'/'processed'/'snapshots.csv'
    if not path.exists():
        from prepare_data import main
        main()
    frame=pd.read_csv(path,dtype={'checkpoint':str},low_memory=False)
    splits=assign_splits(frame,args.seed)
    frame['split']=splits
    args.output.mkdir(parents=True,exist_ok=True)
    frame[['group','source','subject','course_record','checkpoint','target','split']].to_csv(args.output/'split_assignments.csv',index=False)
    write_json(args.output/'protocol.json',{'seed':args.seed,'features':FEATURES,'snapshots_sha256':sha256(path),
        'unseen_subject':'GGG','split_group':'student identity across courses/checkpoints',
        'selection':'validation macro-source accuracy with macro failure recall >= '+str(args.min_recall)+'; tie: lower validation BCE',
        'test_policy':'No test or held-out-subject predictions until architecture, calibration and threshold are fixed.',
        'old_uci_tests':'Previously inspected school data are retrospective development evidence, not a new external validation.'})
    subsets={name:frame.loc[frame.split==name].copy().reset_index(drop=True) for name in np.unique(splits)}
    for name,part in subsets.items():print(f'{name:20s} rows={len(part):6d} students={part.group.nunique():5d} failures={int(part.target.sum()):5d}')
    device='cuda' if args.device!='cpu' and torch.cuda.is_available() else 'cpu'
    if args.device=='cuda' and device!='cuda':raise RuntimeError('Requested CUDA is unavailable')
    print('Interpreter:',sys.executable,'PyTorch:',torch.__version__,'device:',device)
    if device=='cuda':print('GPU:',torch.cuda.get_device_name(0))
    candidates=[
        {'hidden':[],'dropout':0.,'lr':.003,'weight_decay':.01},
        {'hidden':[16],'dropout':.10,'lr':.002,'weight_decay':.03},
        {'hidden':[32,16],'dropout':.15,'lr':.001,'weight_decay':.02},
        {'hidden':[64,32],'dropout':.20,'lr':.001,'weight_decay':.02},
    ]
    histories,search,best_model,best_info,best_key={},[],None,None,None
    for config in candidates:
        name='linear' if not config['hidden'] else '_'.join(map(str,config['hidden']))
        print('\nTraining candidate',name,flush=True)
        model,history,summary=train_candidate(subsets['train'],subsets['validation'],config,args,device)
        histories[name]=history
        pd.DataFrame(history).to_csv(args.output/f'history_{name}.csv',index=False)
        search.append(summary)
        m=summary['validation']
        key=(int(summary['recall_constraint_met']),m['accuracy'],m['balanced_accuracy'],-m['log_loss'])
        if best_key is None or key>best_key:
            best_model,best_info,best_key=model,summary,key
        else:del model
    print('\nSelected architecture BEFORE test evaluation:',best_info['config'],flush=True)
    write_json(args.output/'search.json',{'candidates':search,'selected':best_info})
    model=best_model
    cal=subsets['calibration']
    raw=predict_arrays(model,cal[FEATURES].to_numpy(dtype=np.float32),device,calibrated=False)
    clipped=np.clip(raw,1e-6,1-1e-6)
    matrix=np.column_stack([np.log(clipped/(1-clipped)),cal.university.to_numpy()])
    calibration=LogisticRegression(C=.3,max_iter=2000).fit(matrix,cal.target,sample_weight=source_weights(cal))
    coefficients=np.r_[calibration.coef_[0],calibration.intercept_[0]]
    if coefficients[0]<=0:raise RuntimeError('Calibration inverted model ordering; do not deploy this model')
    model.calibration.copy_(torch.tensor(coefficients,dtype=torch.float32,device=device))
    p=predict_arrays(model,cal[FEATURES].to_numpy(dtype=np.float32),device)
    threshold,thresholds,feasible=choose_threshold(cal,p,args.min_recall)
    model.threshold.copy_(torch.tensor(threshold,device=device))
    pd.DataFrame(thresholds).to_csv(args.output/'threshold_selection.csv',index=False)
    metadata={'format_version':1,'created_at_utc':datetime.now(timezone.utc).isoformat(),
        'seed':args.seed,'threshold':threshold,'calibration_recall_constraint_met':feasible,
        'features':FEATURES,'selected_epoch':best_info['best_epoch'],'selection':best_info,
        'snapshot_data_sha256':sha256(path),'training_sources':['UCI Student Performance','OULAD graded course completers'],
        'subject_name_is_feature':False,'target':'Final course failure; OULAD withdrawal excluded',
        'scope':'Research prototype. High-school validation uses two historical subjects; university results do not validate every high-school course.',
        'timing_assumptions':['UCI first/second period timing proxies','OULAD score assumed available 14 days after submission; actual release dates unavailable'],
        'environment':{'python':platform.python_version(),'torch':str(torch.__version__),'numpy':np.__version__,'pandas':pd.__version__,'sklearn':sklearn.__version__,'device':device},
        'attribution':['Cortez (2008), UCI Student Performance, DOI 10.24432/C5TG7T, CC BY 4.0','Kuzilek et al., OULAD, DOI 10.24432/C5KK69, CC BY 4.0']}
    artifact=args.output/'course_risk.pt'
    temporary=artifact.with_suffix('.pt.part')
    torch.save({'features':FEATURES,'architecture':{'hidden':best_info['config']['hidden'],'dropout':best_info['config']['dropout']},
        'state_dict':{key:value.detach().cpu() for key,value in model.state_dict().items()},'metadata':metadata},temporary)
    load_model(temporary)
    temporary.replace(artifact)
    write_json(args.output/'model_card.json',metadata)

    # Baselines are evidence only, never saved as extra deployable model artifacts.
    train=subsets['train']
    baseline=make_pipeline(SimpleImputer(strategy='median',add_indicator=True),LogisticRegression(C=.3,max_iter=2000))
    baseline.fit(train[FEATURES],train.target,logisticregression__sample_weight=source_weights(train))
    trees=HistGradientBoostingClassifier(max_iter=150,max_leaf_nodes=15,l2_regularization=5,random_state=args.seed,early_stopping=False)
    trees.fit(train[FEATURES],train.target,sample_weight=source_weights(train))
    results={'selected_model':'one shared PyTorch model','threshold':threshold,'partitions':{},'baselines':{}}
    reload_model,_=load_model(artifact)
    for name,part in subsets.items():
        x=part[FEATURES].to_numpy(dtype=np.float32)
        p=predict_arrays(model,x,device)
        if name in {'test','unseen_subject_test'}:
            np.testing.assert_allclose(predict_arrays(reload_model,x),p,rtol=1e-5,atol=1e-6)
        results['partitions'][name]={'selected_threshold':grouped_report(part,p,threshold),'fixed_0_5':grouped_report(part,p,.5)}
        records=part[['group','source','subject','course_record','checkpoint','target','split']].copy()
        records['probability']=p;records['predicted_fail']=p>=threshold
        records.to_csv(args.output/f'{name}_predictions.csv',index=False)
        if name in {'test','unseen_subject_test'}:
            results['partitions'][name]['student_cluster_95pct_ci']=cluster_bootstrap(part,p,threshold,args.seed)
            results['baselines'][name]={
                'latest_grade_rule':grouped_report(part,(part.current_grade<part.passing_grade).to_numpy(dtype=float),.5),
                'logistic_regression':grouped_report(part,baseline.predict_proba(part[FEATURES])[:,1],.5),
                'gradient_boosting':grouped_report(part,trees.predict_proba(part[FEATURES])[:,1],.5)}
    write_json(args.output/'metrics.json',results)
    (args.output/'model.sha256').write_text(sha256(artifact),encoding='ascii')
    validation_predictions=pd.read_csv(args.output/'validation_predictions.csv')
    samples=pd.concat([validation_predictions.loc[validation_predictions.source==source].groupby('target',group_keys=False).head(4) for source in ['school','oulad']],ignore_index=True)
    samples.to_csv(args.output/'validation_samples.csv',index=False)
    from report import create_report
    create_report(args.output,results,histories)
    for partition in ['test','unseen_subject_test']:
        print('\n'+partition.upper()+' | calibrated probabilities, frozen threshold',flush=True)
        for key,value in results['partitions'][partition]['selected_threshold'].items():
            if key=='macro_source':continue
            print(f"{key:25s} n={value['n']:5d} accuracy={value['accuracy']:.4f} precision={value['precision']:.4f} recall={value['recall']:.4f} F1={value['f1']:.4f} loss={value['log_loss']:.4f}")
    print('\nSaved-model CPU reload matches GPU predictions. ONE exported model:',artifact)
    print('Report:',args.output/'report.html')


if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output',type=Path,default=ROOT/'model')
    parser.add_argument('--device',choices=['auto','cpu','cuda'],default='auto')
    parser.add_argument('--seed',type=int,default=20261007)
    parser.add_argument('--epochs',type=int,default=150)
    parser.add_argument('--patience',type=int,default=20)
    parser.add_argument('--samples-per-epoch',type=int,default=8192)
    parser.add_argument('--batch-size',type=int,default=256)
    parser.add_argument('--min-recall',type=float,default=.70)
    args=parser.parse_args()
    if min(args.epochs,args.patience,args.samples_per_epoch,args.batch_size)<1 or not 0<=args.min_recall<=1:parser.error('Invalid training counts or recall target')
    if (args.output/'course_risk.pt').exists():raise SystemExit('Preserving existing artifact. Use --output with a new experiment folder.')
    args.output.mkdir(parents=True,exist_ok=True)
    stream=sys.stdout
    tee=Tee(stream,args.output/'training.log');sys.stdout=tee
    try:run(args)
    finally:sys.stdout=stream;tee.file.close()
