"""Repair report-only checkpoint labels and regenerate evaluation without model tuning."""
import json
import os
os.environ.setdefault('LOKY_MAX_CPU_COUNT','2')
from pathlib import Path
import numpy as np
import pandas as pd
from sklearn.ensemble import HistGradientBoostingClassifier
from sklearn.impute import SimpleImputer
from sklearn.linear_model import LogisticRegression
from sklearn.pipeline import make_pipeline

from download_data import ROOT,sha256
from model import FEATURES,load_model,predict_arrays
from metrics import grouped_report,cluster_bootstrap
from train import source_weights,write_json
from report import create_report


def refresh():
    folder=ROOT/'model'
    model,metadata=load_model(folder/'course_risk.pt')
    path=ROOT/'data'/'processed'/'snapshots.csv'
    if sha256(path)!=metadata['snapshot_data_sha256']:raise ValueError('Source data changed')
    data=pd.read_csv(path,dtype={'checkpoint':str},low_memory=False)
    assignment=pd.read_csv(folder/'split_assignments.csv',dtype={'checkpoint':str})
    if not data[['group','course_record']].equals(assignment[['group','course_record']]):raise ValueError('Row identity changed')
    # The original chunked CSV reader mixed string 0.50 and float 0.5 labels.
    # Only display labels are replaced; student assignment and features stay fixed.
    assignment['checkpoint']=data.checkpoint
    assignment.to_csv(folder/'split_assignments.csv',index=False)
    data['split']=assignment.split
    results=json.loads((folder/'metrics.json').read_text())
    threshold=results['threshold']
    for split,part in data.groupby('split',sort=False):
        part=part.reset_index(drop=True)
        probability=predict_arrays(model,part[FEATURES].to_numpy(dtype=np.float32))
        original=pd.read_csv(folder/f'{split}_predictions.csv')
        np.testing.assert_allclose(original.probability,probability,rtol=1e-5,atol=1e-6)
        record=part[['group','source','subject','course_record','checkpoint','target','split']].copy()
        record['probability']=probability;record['predicted_fail']=probability>=threshold
        record.to_csv(folder/f'{split}_predictions.csv',index=False)
        results['partitions'][split]['selected_threshold']=grouped_report(part,probability,threshold)
        results['partitions'][split]['fixed_0_5']=grouped_report(part,probability,.5)
    # Baseline uses only training records; no internal random snapshot validation.
    train=data[data.split=='train']
    baseline=make_pipeline(SimpleImputer(strategy='median',add_indicator=True),LogisticRegression(C=.3,max_iter=2000))
    baseline.fit(train[FEATURES],train.target,logisticregression__sample_weight=source_weights(train))
    trees=HistGradientBoostingClassifier(max_iter=150,max_leaf_nodes=15,l2_regularization=5,random_state=metadata['seed'],early_stopping=False)
    trees.fit(train[FEATURES],train.target,sample_weight=source_weights(train))
    for split in ['test','unseen_subject_test']:
        part=data[data.split==split]
        results['baselines'][split]={
            'latest_grade_rule':grouped_report(part,(part.current_grade<part.passing_grade).to_numpy(dtype=float),.5),
            'logistic_regression':grouped_report(part,baseline.predict_proba(part[FEATURES])[:,1],.5),
            'gradient_boosting':grouped_report(part,trees.predict_proba(part[FEATURES])[:,1],.5)}
    validation=pd.read_csv(folder/'validation_predictions.csv',dtype={'checkpoint':str})
    samples=pd.concat([validation[validation.source==source].groupby('target',group_keys=False).head(4) for source in ['school','oulad']],ignore_index=True)
    samples.to_csv(folder/'validation_samples.csv',index=False)
    write_json(folder/'metrics.json',results)
    histories={path.stem.removeprefix('history_'):pd.read_csv(path).to_dict(orient='records') for path in folder.glob('history_*.csv')}
    create_report(folder,results,histories)
    write_json(folder/'report_repair.json',{'checkpoint_display_labels_normalized':True,'model_weights_changed':False,'threshold_changed':False,'test_predictions_unchanged':True,'gradient_baseline_early_stopping':False})
    print('Report refreshed. Model weights, threshold, data, split membership, and predictions are unchanged.')


if __name__=='__main__':refresh()
