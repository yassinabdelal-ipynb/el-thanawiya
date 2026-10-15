"""Export the existing trained model's weights; no retraining or new classifier."""
import copy, hashlib, json, sys
from pathlib import Path
import numpy as np
import torch

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT.parent / 'academic-risk'
sys.path.insert(0, str(SOURCE))
from model import FEATURES, load_model, predict_arrays
from features import course_features
from datetime import date

checkpoint = SOURCE / 'model' / 'course_risk.pt'
model, metadata = load_model(checkpoint)
layers = [{'weight': layer.weight.detach().tolist(), 'bias': layer.bias.detach().tolist()}
          for layer in model.network if isinstance(layer, torch.nn.Linear)]
asset = {'schema_version': 1, 'features': FEATURES, 'layers': layers,
         'median': model.median.tolist(), 'mean': model.mean.tolist(), 'scale': model.scale.tolist(),
         'margin_strength': model.margin_strength.item(), 'calibration': model.calibration.tolist(),
         'threshold': model.threshold.item(), 'scope': metadata['scope'],
         'source_sha256': hashlib.sha256(checkpoint.read_bytes()).hexdigest()}
assets = ROOT / 'assets'; assets.mkdir(exist_ok=True)
(assets / 'course_risk.json').write_text(json.dumps(asset, separators=(',', ':')), encoding='utf-8')

random = np.random.default_rng(90210)
# Synthetic numerical test vectors cover broad ranges and missing optional fields.
matrix = random.uniform(0, 1, (600, len(FEATURES))).astype(np.float32)
matrix[:, 2] = random.uniform(-1, 1, len(matrix))
matrix[:, 5] = random.uniform(0.69, 4.5, len(matrix))
matrix[:, -1] = random.integers(0, 2, len(matrix))
matrix[random.random(matrix.shape) < .25] = np.nan
matrix[:, [0, 4, 9, 13]] = random.uniform(0, 1, (len(matrix), 4))
matrix[:, -1] = random.integers(0, 2, len(matrix))
probabilities = predict_arrays(model, matrix)
vectors = [{'features': [None if np.isnan(x) else float(x) for x in row], 'probability': float(p)}
           for row, p in zip(matrix, probabilities)]

student = json.loads((SOURCE / 'examples' / 'student.json').read_text())
payloads = [student]
for mode in range(6):
    payload = copy.deepcopy(student); payload['courses'] = [payload['courses'][0]]
    course = payload['courses'][0]
    if mode == 0: course.pop('current_grade'); course.pop('current_grade_available_on')
    if mode == 1:
        course['assessment_schedule_complete'] = True
        course['assessments'].append({'due_date': '2026-10-03', 'weight': 2})
        course['assessments'].append({'due_date': '2026-11-12', 'weight': 3})
    if mode == 2:
        course['assessments'][1]['available_on'] = '2026-10-10'
    if mode == 3:
        course['assessments'] = []; course['previous_failures'] = 8; course['study_hours_per_week'] = 12
    if mode == 4:
        for item in course['assessments']: item['weight'] = 0
        course.pop('current_grade'); course.pop('current_grade_available_on')
        course['assessment_schedule_complete'] = True
    if mode == 5:
        payload['education_level'] = 'university'
        course['assessments'].append({'type': 'final_exam', 'score': 1})
    payloads.append(payload)
fixtures = []
for payload in payloads:
    courses = []
    for course in payload['courses']:
        value, details = course_features(course, date.fromisoformat(payload['as_of']), payload['education_level'])
        ordered = [value[key] for key in FEATURES] if value else None
        probability = float(predict_arrays(model, np.array([ordered], dtype=np.float32))[0]) if ordered else None
        courses.append({'features': [None if np.isnan(x) else x for x in ordered] if ordered else None,
                        'probability': probability, 'details': details})
    fixtures.append({'payload': payload, 'expected': courses})
(assets / 'demo_student.json').write_text(json.dumps(student), encoding='utf-8')
(ROOT / 'test' / 'fixtures').mkdir(parents=True, exist_ok=True)
(ROOT / 'test' / 'fixtures' / 'parity.json').write_text(json.dumps({'vectors': vectors, 'payloads': fixtures}, allow_nan=False), encoding='utf-8')
print(f'Exported the original model: {asset["source_sha256"]}; {len(vectors)} numerical parity cases, {len(fixtures)} input fixtures.')
