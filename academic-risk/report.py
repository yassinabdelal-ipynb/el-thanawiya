"""Verified static graphs and a self-contained HTML experiment report."""
from pathlib import Path
import os
os.environ.setdefault('MPLCONFIGDIR',str(Path(__file__).resolve().parent/'.mplconfig'))
import html
import json
import matplotlib
matplotlib.use('Agg')
import matplotlib.pyplot as plt
import numpy as np
import pandas as pd
from sklearn.calibration import calibration_curve
from sklearn.metrics import ConfusionMatrixDisplay,precision_recall_curve,roc_curve


def save(fig,path):
    fig.tight_layout()
    fig.savefig(path,dpi=160,bbox_inches='tight',facecolor=fig.get_facecolor())
    plt.close(fig)


def create_report(folder,results,histories):
    plt.rcParams.update({'figure.facecolor':'#f8fafc','axes.facecolor':'white',
        'axes.spines.right':False,'axes.spines.top':False,'axes.titleweight':'bold',
        'font.family':'DejaVu Sans','font.size':10})
    plots=folder/'plots';plots.mkdir(exist_ok=True)
    fig,axes=plt.subplots(len(histories),2,figsize=(12,3.2*len(histories)),squeeze=False)
    for row,(name,records) in enumerate(histories.items()):
        frame=pd.DataFrame(records)
        for col,metric in enumerate(['loss','accuracy']):
            ax=axes[row,col]
            ax.plot(frame.epoch,frame[f'train_{metric}'],label='Training batches',color='#0891b2')
            ax.plot(frame.epoch,frame[f'validation_{metric}'],label='Validation; equal source weighting',color='#7c3aed')
            ax.set(title=f'{name} | {"BCE loss" if col==0 else "Accuracy at raw 0.50"}',xlabel='Epoch',ylabel=metric)
            if col==1:ax.set_ylim(0,1.02)
            else:ax.set_ylim(bottom=0)
            ax.legend(fontsize=8);ax.grid(alpha=.15)
    save(fig,plots/'learning_curves.png')
    test=pd.read_csv(folder/'test_predictions.csv')
    unseen=pd.read_csv(folder/'unseen_subject_test_predictions.csv')
    sets={'School: first checkpoint':test[(test.source=='school')&(test.checkpoint=='first')],
        'School: second checkpoint':test[(test.source=='school')&(test.checkpoint=='second')],
        'University: seen modules, new students':test[test.source=='oulad'],
        'University: entirely held-out GGG module':unseen[unseen.subject=='GGG']}
    fig,axes=plt.subplots(2,2,figsize=(11,9))
    for ax,(name,frame) in zip(axes.flat,sets.items()):
        ConfusionMatrixDisplay.from_predictions(frame.target,frame.probability>=results['threshold'],labels=[0,1],display_labels=['Pass','Fail'],cmap='Purples',colorbar=False,ax=ax)
        ax.set_title(name+'\nFrozen calibration-selected threshold')
    save(fig,plots/'confusion_matrices.png')
    fig,axes=plt.subplots(1,2,figsize=(13,5))
    for color,(name,frame) in zip(['#0891b2','#7c3aed','#d97706','#059669'],sets.items()):
        fpr,tpr,_=roc_curve(frame.target,frame.probability)
        precision,recall,_=precision_recall_curve(frame.target,frame.probability)
        axes[0].plot(fpr,tpr,color=color,label=name)
        axes[1].plot(recall,precision,color=color,label=name)
    axes[0].plot([0,1],[0,1],'--',color='#94a3b8')
    axes[0].set(title='ROC',xlabel='False-positive rate',ylabel='Failure recall')
    axes[1].set(title='Precision-recall',xlabel='Failure recall',ylabel='Alert precision')
    for ax in axes:ax.legend(fontsize=7,loc='lower left');ax.set(xlim=(0,1),ylim=(0,1.02));ax.grid(alpha=.15)
    save(fig,plots/'roc_precision_recall.png')
    fig,axes=plt.subplots(2,2,figsize=(11,9))
    for ax,(name,frame) in zip(axes.flat,sets.items()):
        actual,probability=calibration_curve(frame.target,frame.probability,n_bins=6,strategy='uniform')
        ax.plot([0,1],[0,1],'--',color='#94a3b8');ax.plot(probability,actual,'o-',color='#7c3aed')
        ax.set(title=name,xlabel='Mean predicted failure probability',ylabel='Observed failure fraction',xlim=(0,1),ylim=(0,1));ax.grid(alpha=.15)
    save(fig,plots/'calibration.png')
    from metrics import scores
    fig,axes=plt.subplots(1,3,figsize=(14,4.5))
    labels=list(sets)
    for ax,key in zip(axes,['accuracy','recall','precision']):
        tuned=[scores(frame.target.to_numpy(),frame.probability.to_numpy(),results['threshold'])[key] for frame in sets.values()]
        fixed=[scores(frame.target.to_numpy(),frame.probability.to_numpy(),.5)[key] for frame in sets.values()]
        positions=np.arange(len(labels))
        ax.bar(positions-.18,tuned,width=.36,color='#7c3aed',label='Frozen alert threshold')
        ax.bar(positions+.18,fixed,width=.36,color='#0891b2',label='Fixed 0.50')
        ax.set(title=key.title(),xticks=positions,xticklabels=['School\nfirst','School\nsecond','University\nseen','University\nunseen'],ylim=(0,1.08));ax.grid(axis='y',alpha=.15)
    axes[0].legend(fontsize=8)
    save(fig,plots/'operating_points.png')
    flat=[]
    for partition,data in results['partitions'].items():
        for policy in ['selected_threshold','fixed_0_5']:
            for label,m in data[policy].items():
                if label=='macro_source':continue
                flat.append({'partition':partition,'policy':policy,'group':label,**{k:v for k,v in m.items() if k!='confusion_matrix'}})
    pd.DataFrame(flat).to_csv(folder/'metrics.csv',index=False)
    score_rows=[]
    for name,frame in sets.items():
        m=scores(frame.target.to_numpy(),frame.probability.to_numpy(),results['threshold'])
        score_rows.append('<tr><td>'+html.escape(name)+'</td>'+''.join(f'<td>{m[k]:.3f}</td>' for k in ['accuracy','precision','recall','f1','roc_auc','average_precision','log_loss'])+f'<td>{len(frame)}</td></tr>')
    card=json.loads((folder/'model_card.json').read_text())
    samples=pd.read_csv(folder/'validation_samples.csv')
    figures=[('learning_curves.png','Training and validation'),('confusion_matrices.png','Failures detected and false alerts'),('roc_precision_recall.png','Ranking performance'),('calibration.png','Probability reliability'),('operating_points.png','Alert-threshold tradeoff')]
    figure_html=''.join(f'<section><h2>{title}</h2><img src="plots/{file}" alt="{title}"></section>' for file,title in figures)
    output=f'''<!doctype html><html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>One course-risk model</title>
<style>body{{margin:0;background:#f1f5f9;color:#0f172a;font:16px/1.6 system-ui,sans-serif}}main{{max-width:1160px;margin:auto;padding:30px 20px}}section,header{{background:white;border:1px solid #e2e8f0;border-radius:15px;padding:24px;margin-bottom:22px}}h1{{font-size:35px;line-height:1.2}}h2{{font-size:23px}}img{{width:100%;height:auto}}.scroll{{overflow:auto}}table{{border-collapse:collapse;width:100%;font-size:13px}}td,th{{padding:9px;border-bottom:1px solid #e2e8f0;white-space:nowrap;text-align:left}}th{{background:#f8fafc}}a{{color:#6d28d9}}.muted{{color:#475569}}code{{background:#f1f5f9;padding:3px}}</style></head><body><main>
<header><p style="color:#6d28d9;font-weight:700">ONE PYTORCH MODEL · ANY COURSE DISPLAY NAME</p><h1>Course failure risk from observed grades</h1><p>Shared model: <code>course_risk.pt</code>. Hidden layers: {card['selection']['config']['hidden']}. Frozen alert threshold: {results['threshold']:.3f}.</p><p class="muted">Inputs are numerical grade history, grading policy, course progress, available assignment information, and optional study context. Subject name is not a model feature.</p></header>
<section><h2>Evaluation by population and prediction point</h2><div class="scroll"><table><thead><tr><th>Evaluation set</th><th>Accuracy</th><th>Precision</th><th>Recall</th><th>F1</th><th>ROC-AUC</th><th>Average precision</th><th>Log loss ↓</th><th>Records</th></tr></thead><tbody>{''.join(score_rows)}</tbody></table></div><p>Fail is the positive class. School checkpoints and university assessments have different timing and outcome policies. Later-checkpoint accuracy is not an early-warning accuracy claim. Student groups never cross training, validation, calibration, and test partitions.</p></section>
{figure_html}
<section><h2>Validation examples</h2><p>Examples were involved in architecture selection; they are not independent test observations.</p><div class="scroll">{samples.to_html(index=False,escape=True,float_format=lambda v:f'{v:.3f}')}</div></section>
<section><h2>Scope of the evidence</h2><ul><li>School source: historical Mathematics and Portuguese records, with conservative identity grouping. Previously inspected UCI data are development evidence.</li><li>OULAD source: Fail versus Pass/Distinction among graded university course completers. Withdrawal is excluded. All observations from students in module GGG were reserved; that module was absent from model selection and calibration.</li><li>OULAD has submission dates but lacks actual score-release dates. A 14-day release lag is assumed. Final examinations and banked scores are excluded. UCI uses coarse grading-period progress proxies.</li><li>Any subject name can be supplied to the Python interface. Accuracy on a new subject, school, grading policy, or population remains unverified until tested there.</li><li>Absence counts and extracurricular hours do not influence the model. Study bands and participation flags are represented only in the school training data. Recommendations are transparent observations, not estimated causal effects.</li><li>Cluster bootstrap intervals account for repeated student records, but not every source of training and model-selection uncertainty.</li></ul><p>Data: <a href="https://archive.ics.uci.edu/dataset/320/student+performance">UCI Student Performance</a> and <a href="https://archive.ics.uci.edu/dataset/349/open+university+learning+analytics+dataset">OULAD</a>, both CC BY 4.0. Halabja annual data were downloaded and audited but excluded from training.</p><p><a href="metrics.json">Full metrics</a> · <a href="metrics.csv">Metrics CSV</a> · <a href="model_card.json">Model card</a> · <a href="validation_samples.csv">Validation examples</a> · <a href="training.log">Training log</a></p></section></main></body></html>'''
    (folder/'report.html').write_text(output,encoding='utf-8')
