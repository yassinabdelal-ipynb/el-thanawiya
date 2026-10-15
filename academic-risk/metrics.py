"""Metrics with failure as the positive class and student-cluster uncertainty."""
import numpy as np
from sklearn.metrics import (accuracy_score, balanced_accuracy_score, brier_score_loss,
    confusion_matrix, f1_score, log_loss, precision_score, recall_score, roc_auc_score,
    average_precision_score)


def scores(y, probability, threshold=0.5):
    pred = probability >= threshold
    two_classes = len(np.unique(y)) == 2
    return {'n':len(y), 'failures':int(np.sum(y)), 'threshold':float(threshold),
        'accuracy':float(accuracy_score(y,pred)), 'balanced_accuracy':float(balanced_accuracy_score(y,pred)),
        'precision':float(precision_score(y,pred,zero_division=0)), 'recall':float(recall_score(y,pred,zero_division=0)),
        'f1':float(f1_score(y,pred,zero_division=0)),
        'roc_auc':float(roc_auc_score(y,probability)) if two_classes else None,
        'average_precision':float(average_precision_score(y,probability)) if two_classes else None,
        'log_loss':float(log_loss(y,probability,labels=[0,1])), 'brier':float(brier_score_loss(y,probability)),
        'confusion_matrix':confusion_matrix(y,pred,labels=[0,1]).tolist()}


def macro_source_scores(frame, p, threshold):
    results = []
    for source in frame.source.unique():
        mask = frame.source.to_numpy()==source
        results.append(scores(frame.target.to_numpy()[mask],p[mask],threshold))
    return {key:float(np.mean([record[key] for record in results])) for key in ['accuracy','balanced_accuracy','recall','precision','f1','log_loss']}


def choose_threshold(frame,p,min_recall=0.7):
    table = []
    for threshold in np.linspace(0.05,0.95,181):
        table.append({'threshold':float(threshold), **macro_source_scores(frame,p,threshold)})
    feasible = [row for row in table if row['recall']>=min_recall]
    pool = feasible or table
    best = max(pool,key=lambda row:(row['accuracy'],row['balanced_accuracy'],row['precision']))
    return best['threshold'],table,bool(feasible)


def grouped_report(frame,p,threshold):
    result = {'all':scores(frame.target.to_numpy(),p,threshold)}
    for column in ['source','subject','checkpoint']:
        for value in frame[column].unique():
            mask=frame[column].to_numpy()==value
            result[f'{column}:{value}']=scores(frame.target.to_numpy()[mask],p[mask],threshold)
    result['macro_source']=macro_source_scores(frame,p,threshold)
    return result


def cluster_bootstrap(frame,p,threshold,seed=42,repeats=250):
    # Multiple course/checkpoint records belonging to one student are sampled together.
    rng=np.random.default_rng(seed)
    positions={group:np.flatnonzero(frame.group.to_numpy()==group) for group in frame.group.unique()}
    groups=list(positions)
    values={key:[] for key in ['accuracy','recall','precision','f1']}
    y=frame.target.to_numpy()
    for _ in range(repeats):
        sampled=rng.choice(groups,len(groups),replace=True)
        indices=np.concatenate([positions[group] for group in sampled])
        value=scores(y[indices],p[indices],threshold)
        for key in values:values[key].append(value[key])
    return {key:[float(np.percentile(value,2.5)),float(np.percentile(value,97.5))] for key,value in values.items()}
