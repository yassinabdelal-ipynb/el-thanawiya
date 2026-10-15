# Course-risk inference and research pipeline

This directory contains the shared PyTorch model, validated JSON interface, localhost HTTP API, and reproducible training/evaluation code. It is also the source of the Flutter app's exported model.

## Setup and prediction

Use Python 3.10–3.12 and a virtual environment. Inference works on CPU; no training is required.

```sh
python -m venv .venv
# Activate .venv for your shell.
python -m pip install -r requirements.txt
python predict.py --input examples/student.json
python predict.py --input examples/student.json --output predictions.json
```

To integrate in Python:

```python
from predict import CourseRiskPredictor

predictor = CourseRiskPredictor()  # Load the shared checkpoint once.
result = predictor.predict_student(student_payload)
```

The included example is illustrative. It covers Mathematics, a reversed German grade scale, and Chemistry without observed marks; it is not validation evidence for those example subjects.

## Input contract

```json
{
  "as_of": "2026-10-07",
  "education_level": "high_school",
  "courses": [{
    "name": "History",
    "term_start": "2026-09-01",
    "term_end": "2026-12-20",
    "grade_min": 0,
    "grade_max": 100,
    "higher_is_better": true,
    "passing_grade": 50,
    "current_grade": 65,
    "current_grade_available_on": "2026-10-06",
    "credits": 2
  }]
}
```

`education_level` is `high_school` or `university`. Each course needs explicit grading bounds, direction, passing policy, and term dates. Set `higher_is_better` to `false` for a reversed scale such as 1–6 where 1 is strongest.

For history, supply `assessments` with `score`, `due_date`, and `available_on`; optional fields are `submitted_on` and a nonnegative relative `weight`. Scores available after `as_of` are ignored. `type` may be `assessment`, `period`, or `final_exam`; final exams are excluded. Without an official current grade, observed assessments supply a weighted mean. Missing grades are not treated as zero.

Set `assessment_schedule_complete` to `true` only when all non-final assessments, including future and missing work, are included. Otherwise coverage and overdue fractions stay unknown.

Optional course inputs are `previous_failures`, `study_hours_per_week`, and boolean `extracurricular_participation`. Leave unknown values absent. The current model does not use attendance, extracurricular hours, or topic mastery.

Output includes course-level failure probabilities, alerts, input observations, missing fields, coverage, expected failed-course count among predicted courses, and a credit-weighted priority score. The aggregate score is not the probability of failing the whole term.

Override the application alert threshold without changing model probabilities:

```sh
python predict.py --input examples/student.json --alert-threshold 0.5
```

## Local API

```sh
python serve.py --port 8000 --allow-origin http://localhost:3000
```

- `GET http://127.0.0.1:8000/health`
- `POST http://127.0.0.1:8000/predict` with the JSON payload.

Invalid input returns 400. Unapproved browser origins return 403. The server binds only to localhost and loads one checkpoint once. This is a local development interface, with no production authentication or student database.

## Checks

```sh
python -m unittest discover -s tests -v
```

The 17-test suite covers temporal leakage, grading orientation, missingness, grouped partitions, subject-name invariance, aggregation, checkpoint predictions, and HTTP/CORS behavior. Three research-data tests skip until the processed data exists.

## Reproduce research results

```sh
python download_data.py
python prepare_data.py
python evaluate.py
```

Downloads validate source checksums and extract only allowlisted files. `evaluate.py` verifies the prepared data checksum, frozen split ordering, model checksum, saved probabilities, and metrics. It does not retrain or tune against the test set. The original processed-table checksum must match for exact reproduction; library or source changes should be investigated rather than bypassing the check.

To train a separate artifact:

```sh
python train.py --output runs/reproduction --device cpu
```

PowerShell also supports `./run_training.ps1 -Output runs/reproduction`. Existing artifact files are protected from accidental overwrite. Keep the shipped checkpoint fixed unless deliberately releasing a new model. Raw and processed datasets and reproduction runs are ignored by Git.

## Evaluation and provenance

See the [model card](../docs/MODEL_CARD.md), `model/report.html`, `model/metrics.csv`, and `model/protocol.json`. The model covers historical school Mathematics/Portuguese data and OULAD graded completers; new subjects remain unvalidated. OULAD withdrawals are excluded. Halabja annual grades were audited but excluded from training and redistribution.

UCI Student Performance: Cortez (2008), DOI 10.24432/C5TG7T. OULAD: Kuzilek et al., DOI 10.24432/C5KK69. Source attribution and CC BY 4.0 notices are retained in [THIRD_PARTY_NOTICES.txt](../THIRD_PARTY_NOTICES.txt).
