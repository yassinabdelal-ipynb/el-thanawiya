"""Checks for temporal leakage, unit handling, grouping, and the app interface."""
from copy import deepcopy
from datetime import date
import json
from pathlib import Path
import sys
import threading
import unittest
from urllib.error import HTTPError
from urllib.request import Request,urlopen

sys.path.insert(0,str(Path(__file__).resolve().parents[1]))
import numpy as np
import pandas as pd
import torch
from features import normalize_grade,course_features
from model import FEATURES,CourseRiskModel,load_model,predict_arrays
from predict import CourseRiskPredictor
from train import assign_splits
from serve import create_server

ROOT=Path(__file__).resolve().parents[1]


class InputTests(unittest.TestCase):
    def setUp(self):
        self.payload=json.loads((ROOT/'examples'/'student.json').read_text())
        self.course=deepcopy(self.payload['courses'][0])
        self.today=date(2026,10,7)

    def test_grade_scales_and_direction(self):
        self.assertAlmostEqual(normalize_grade(10,0,20),.5)
        self.assertAlmostEqual(normalize_grade(50,0,100),.5)
        self.assertAlmostEqual(normalize_grade(1,1,6,False),1.)
        self.assertAlmostEqual(normalize_grade(6,1,6,False),0.)
        for values in [(True,0,100,True),(101,0,100,True),(50,100,0,True),(float('inf'),0,100,True)]:
            with self.assertRaises(ValueError):normalize_grade(*values)

    def test_future_grades_cannot_enter_features(self):
        original,_=course_features(self.course,self.today)
        self.course['assessments'].append({'due_date':'2026-11-01','submitted_on':'2026-11-01','available_on':'2026-11-02','score':100})
        altered,_=course_features(self.course,self.today)
        np.testing.assert_equal(list(original.values()),list(altered.values()))

    def test_final_examination_scores_are_excluded(self):
        original,_=course_features(self.course,self.today)
        self.course['assessments'].append({'type':'final_exam','score':100})
        altered,_=course_features(self.course,self.today)
        np.testing.assert_equal(list(original.values()),list(altered.values()))

    def test_current_grade_cannot_be_from_future(self):
        self.course['current_grade_available_on']='2026-11-01'
        with self.assertRaises(ValueError):course_features(self.course,self.today)

    def test_missing_grades_are_not_assumed_to_be_zero(self):
        values,details=course_features(self.payload['courses'][2],self.today)
        self.assertIsNone(values)
        self.assertEqual(details['status'],'insufficient_data')

    def test_incomplete_schedule_does_not_invent_missing_assignments(self):
        values,_=course_features(self.course,self.today)
        self.assertTrue(np.isnan(values['overdue_fraction']))
        self.assertTrue(np.isnan(values['graded_fraction']))
        self.course['assessment_schedule_complete']=True
        self.course['assessments'].append({'due_date':'2026-10-01','weight':1})
        values,_=course_features(self.course,self.today)
        self.assertAlmostEqual(values['overdue_fraction'],1/3)

    def test_lower_better_grade_trend_uses_quality_direction(self):
        values,_=course_features(self.payload['courses'][1],self.today)
        self.assertLess(values['grade_trend'],0)

    def test_invalid_dates_categories_and_credits_fail_clearly(self):
        for changes in [{'credits':0},{'passing_grade':None},{'term_end':'2026-09-01'},{'higher_is_better':'yes'},{'extracurricular_participation':'yes'},{'study_hours_per_week':float('nan')}]:
            with self.assertRaises(ValueError):course_features({**self.course,**changes},self.today)

    def test_optional_missingness_has_finite_pytorch_gradients(self):
        model=CourseRiskModel(hidden=[8])
        x=np.zeros((3,len(FEATURES)),dtype=np.float32)
        x[:,0]=[.4,.6,.8];x[:,9]=.5;x[:,2]=np.nan
        model.fit_preprocessing(x)
        loss=torch.nn.functional.binary_cross_entropy_with_logits(model(torch.tensor(x)),torch.tensor([1.,0.,0.]))
        loss.backward()
        self.assertTrue(torch.isfinite(loss))
        self.assertTrue(all(torch.isfinite(parameter.grad).all() for parameter in model.parameters()))


class DataAndArtifactTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        data=ROOT/'data'/'processed'/'snapshots.csv'
        cls.frame=pd.read_csv(data,dtype={'checkpoint':str},low_memory=False) if data.exists() else None
        cls.predictor=CourseRiskPredictor()
        cls.payload=json.loads((ROOT/'examples'/'student.json').read_text())

    @unittest.skipUnless((ROOT/'data/processed/snapshots.csv').exists(), 'Run prepare_data.py for research-data checks')
    def test_student_groups_and_entire_course_are_held_out(self):
        parts=assign_splits(self.frame,20261007)
        grouping=pd.DataFrame({'group':self.frame.group,'split':parts})
        self.assertEqual(grouping.groupby('group').split.nunique().max(),1)
        self.assertTrue(np.all(parts[self.frame.subject.to_numpy()=='GGG']=='unseen_subject_test'))

    @unittest.skipUnless((ROOT/'data/processed/snapshots.csv').exists(), 'Run prepare_data.py for research-data checks')
    def test_available_score_dates_do_not_exceed_cutoff(self):
        rows=self.frame[self.frame.source=='oulad']
        self.assertTrue((rows.max_score_available_day<=rows.cutoff_day).all())

    def test_subject_name_does_not_change_prediction(self):
        a=deepcopy(self.payload);a['courses']=a['courses'][:1]
        b=deepcopy(a);b['courses'][0]['name']='Arbitrary new subject'
        original=self.predictor.predict_student(a)['courses'][0]['failure_probability']
        renamed=self.predictor.predict_student(b)['courses'][0]['failure_probability']
        self.assertEqual(original,renamed)

    def test_partial_overall_summary_does_not_hide_missing_course(self):
        output=self.predictor.predict_student(self.payload)
        self.assertEqual(output['overall']['courses_predicted'],2)
        self.assertEqual(output['overall']['courses_total'],3)
        self.assertFalse(output['overall']['complete_coverage'])
        self.assertEqual(output['courses'][2]['status'],'insufficient_data')
        expected=sum(c['failure_probability'] for c in output['courses'] if c['status']=='predicted')
        self.assertAlmostEqual(output['overall']['expected_failed_courses_among_predicted'],expected,places=3)

    def test_application_cutoff_changes_alerts_without_changing_probabilities(self):
        low=CourseRiskPredictor(alert_threshold=0).predict_student(self.payload)
        high=CourseRiskPredictor(alert_threshold=1).predict_student(self.payload)
        for a,b in zip(low['courses'][:2],high['courses'][:2]):
            self.assertEqual(a['failure_probability'],b['failure_probability'])
            self.assertTrue(a['alert']);self.assertFalse(b['alert'])
        self.assertEqual(high['threshold_source'],'application_override')

    def test_invalid_student_payloads_and_final_labels_are_rejected(self):
        bad=[]
        changed=deepcopy(self.payload);changed['courses'][0]['G3']=19;bad.append(changed)
        changed=deepcopy(self.payload);changed['courses']=[42];bad.append(changed)
        changed=deepcopy(self.payload);changed['courses']=[];bad.append(changed)
        changed=deepcopy(self.payload);changed['courses'].append(deepcopy(changed['courses'][0]));bad.append(changed)
        for value in bad:
            with self.assertRaises(ValueError):self.predictor.predict_student(value)

    @unittest.skipUnless((ROOT/'data/processed/snapshots.csv').exists(), 'Run prepare_data.py for research-data checks')
    def test_only_one_model_artifact_and_saved_test_predictions_match(self):
        self.assertEqual(len(list((ROOT/'model').glob('*.pt'))),1)
        stored=pd.read_csv(ROOT/'model'/'test_predictions.csv',dtype={'checkpoint':str})
        assignments=pd.read_csv(ROOT/'model'/'split_assignments.csv',dtype={'checkpoint':str})
        x=self.frame.loc[assignments.split=='test',FEATURES].to_numpy(dtype=np.float32)
        p=predict_arrays(self.predictor.model,x)
        np.testing.assert_allclose(p,stored.probability.to_numpy(),rtol=1e-5,atol=1e-6)

    def test_local_http_api_predicts_and_rejects_invalid_input(self):
        server=create_server(port=0,allow_origin='http://localhost:3000')
        thread=threading.Thread(target=server.serve_forever,daemon=True);thread.start()
        url=f'http://127.0.0.1:{server.server_port}'
        try:
            with urlopen(url+'/health',timeout=10) as response:
                self.assertEqual(json.load(response)['model_count'],1)
            request=Request(url+'/predict',data=json.dumps(self.payload).encode(),headers={'Content-Type':'application/json'})
            with urlopen(request,timeout=10) as response:self.assertEqual(json.load(response)['overall']['courses_predicted'],2)
            bad=Request(url+'/predict',data=b'{"courses":[]}',headers={'Content-Type':'application/json'})
            with self.assertRaises(HTTPError) as context:urlopen(bad,timeout=10)
            self.assertEqual(context.exception.code,400)
            options=Request(url+'/predict',method='OPTIONS',headers={'Origin':'http://localhost:3000'})
            with urlopen(options,timeout=10) as response:self.assertEqual(response.headers['Access-Control-Allow-Origin'],'http://localhost:3000')
            bad_origin=Request(url+'/predict',method='OPTIONS',headers={'Origin':'http://unapproved.example'})
            with self.assertRaises(HTTPError) as context:urlopen(bad_origin,timeout=10)
            self.assertEqual(context.exception.code,403)
        finally:
            server.shutdown();server.server_close();thread.join(timeout=5)


if __name__=='__main__':unittest.main(verbosity=2)
