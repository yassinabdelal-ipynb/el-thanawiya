"""Reproduce frozen model evaluation; never retrain or select a new threshold."""
import argparse
import json
from pathlib import Path
import numpy as np
import pandas as pd

from download_data import ROOT,sha256
from model import FEATURES,load_model,predict_arrays
from metrics import grouped_report


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--model-folder',type=Path,default=ROOT/'model')
    args=parser.parse_args()
    folder=args.model_folder
    data=ROOT/'data'/'processed'/'snapshots.csv'
    model,metadata=load_model(folder/'course_risk.pt')
    if sha256(folder/'course_risk.pt')!=(folder/'model.sha256').read_text().strip():
        raise ValueError('Model checksum changed')
    if sha256(data)!=metadata['snapshot_data_sha256']:
        raise ValueError('Evaluation features differ from the training data')
    frame=pd.read_csv(data,dtype={'checkpoint':str},low_memory=False)
    assignments=pd.read_csv(folder/'split_assignments.csv',dtype={'checkpoint':str})
    if len(frame)!=len(assignments):raise ValueError('Split file length differs from data')
    if not frame[['group','course_record','checkpoint']].astype(str).equals(assignments[['group','course_record','checkpoint']].astype(str)):
        raise ValueError('Split row ordering changed')
    original=json.loads((folder/'metrics.json').read_text())
    results={}
    for split in ['test','unseen_subject_test']:
        rows=np.flatnonzero(assignments.split.to_numpy()==split)
        part=frame.iloc[rows].reset_index(drop=True)
        p=predict_arrays(model,part[FEATURES].to_numpy(dtype=np.float32))
        stored=pd.read_csv(folder/f'{split}_predictions.csv')
        np.testing.assert_allclose(p,stored.probability,rtol=1e-5,atol=1e-6)
        report=grouped_report(part,p,float(model.threshold))
        for group,metrics in report.items():
            if group=='macro_source':continue
            reference=original['partitions'][split]['selected_threshold'][group]
            for key in ['accuracy','precision','recall','f1','log_loss']:
                np.testing.assert_allclose(metrics[key],reference[key],rtol=1e-5,atol=1e-6)
            print(f"{split:20s} {group:25s} accuracy={metrics['accuracy']:.4f} recall={metrics['recall']:.4f} precision={metrics['precision']:.4f} loss={metrics['log_loss']:.4f}")
        results[split]=report
    (folder/'evaluation_verified.json').write_text(json.dumps({'verified':True,'results':results},indent=2,allow_nan=False),encoding='utf-8')
    print('PASS: saved-model predictions and metrics reproduce the original evaluation.')


if __name__=='__main__':main()
