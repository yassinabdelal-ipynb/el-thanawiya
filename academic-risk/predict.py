"""Import CourseRiskPredictor in your app, or run this file with --input student.json."""
from __future__ import annotations

import argparse
from datetime import date
import json
from pathlib import Path
import numpy as np

from model import FEATURES,load_model,predict_arrays
from features import course_features,parse_date,number

DEFAULT_MODEL=Path(__file__).resolve().parent/'model'/'course_risk.pt'


class CourseRiskPredictor:
    def __init__(self,model_path=DEFAULT_MODEL,alert_threshold=None):
        self.model,self.metadata=load_model(Path(model_path))
        self.alert_threshold=float(self.model.threshold) if alert_threshold is None else number(alert_threshold,'alert_threshold',0,1)
        self.threshold_source='model_default' if alert_threshold is None else 'application_override'

    def predict_student(self,payload:dict):
        if not isinstance(payload,dict):raise ValueError('Student input must be a JSON object')
        as_of=parse_date(payload.get('as_of'),'as_of')
        courses=payload.get('courses')
        if not isinstance(courses,list) or not courses:raise ValueError('Provide a nonempty courses list')
        level=payload.get('education_level','high_school')
        features,details,positions=[],[],[]
        seen=set()
        for index,course in enumerate(courses):
            if not isinstance(course,dict):raise ValueError('Every course must be a JSON object')
            if any(key in course for key in ['G3','final_grade','target','actual_fail']):
                raise ValueError('Final outcomes cannot be supplied as prediction inputs')
            value,info=course_features(course,as_of,level)
            key=course.get('id',info['name'])
            if not isinstance(key,str) or key in seen:raise ValueError('Courses need unique names or explicit unique string IDs')
            seen.add(key);info['id']=key
            details.append(info)
            if value is not None:
                features.append([value[name] for name in FEATURES]);positions.append(index)
        if features:
            probability=predict_arrays(self.model,np.array(features,dtype=np.float32))
            for position,p in zip(positions,probability):
                details[position].update({'failure_probability':float(p),'risk_score':round(float(p)*100,2),
                    'alert':bool(p>=self.alert_threshold)})
        predicted=[item for item in details if item['status']=='predicted']
        credits=sum(item['credits'] for item in predicted)
        summary={'courses_total':len(courses),'courses_predicted':len(predicted),'complete_coverage':len(predicted)==len(courses),
            'expected_failed_courses_among_predicted':round(sum(item['failure_probability'] for item in predicted),3),
            'credit_weighted_risk_score':round(sum(item['credits']*item['risk_score'] for item in predicted)/credits,2) if credits else None,
            'priority_order':[item['name'] for item in sorted(predicted,key=lambda item:item['failure_probability'],reverse=True)],
            'interpretation':'Weighted priority score, not the probability of failing the entire term'}
        return {'as_of':as_of.isoformat(),'model':'one shared PyTorch course-risk model','threshold':self.alert_threshold,'threshold_source':self.threshold_source,
            'courses':details,'overall':summary,
            'validation_scope':self.metadata['scope']}


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--model',type=Path,default=DEFAULT_MODEL)
    parser.add_argument('--input',type=Path,required=True)
    parser.add_argument('--output',type=Path)
    parser.add_argument('--alert-threshold',type=float,help='Optional application decision cutoff; does not alter estimated probabilities')
    args=parser.parse_args()
    try:
        payload=json.loads(args.input.read_text(encoding='utf-8-sig'))
        result=CourseRiskPredictor(args.model,args.alert_threshold).predict_student(payload)
    except (ValueError,FileNotFoundError) as error:
        parser.exit(2,f'Input/model error: {error}\n')
    content=json.dumps(result,indent=2,allow_nan=False)
    if args.output:
        args.output.parent.mkdir(parents=True,exist_ok=True)
        args.output.write_text(content,encoding='utf-8')
    print(content)


if __name__=='__main__':main()
