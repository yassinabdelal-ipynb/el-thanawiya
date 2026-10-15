# Validation

## Run on a fresh checkout

```sh
cd forma
flutter pub get
flutter analyze
flutter test
cd ../academic-risk
python -m pip install -r requirements.txt
python -m unittest discover -s tests -v
cd ..
python tools/check_repository.py
```

The Flutter suite covers 21 tests, including 600 numerical parity cases and seven Python/Dart input-contract fixtures. The Python suite contains 17 tests. On a source-only checkout, three tests requiring `data/processed/snapshots.csv` are explicitly skipped. To run those checks, prepare the pinned source data first.

CI executes source checks, Python inference/API tests, Flutter static analysis, and Flutter tests. It does not download the research datasets, retrain, or sign an Android release. Check the linked workflow status for the current commit.

## Publication verification — October 15, 2026

The publication copy passed Flutter static analysis and all 21 Flutter tests. The source-only Python checkout passed 14 tests with three expected research-data skips. After copying the existing checksum-matching processed data into the ignored local data directory, all 17 Python tests passed and `evaluate.py` reproduced the saved probabilities and metrics. The checkpoint and mobile export were unchanged. See [`publication-checks.json`](publication-checks.json).

## Historical release verification

[`verification.json`](verification.json) records previous verification of the supplied Android build and a relocated source build, including checkpoint integrity and reproduced frozen evaluation. These are historical results, not a claim that every checkout or physical device has been tested.

The supplied v1.1.0 APK SHA-256 is:

```text
ed84bf7ba8c7f9d7fee57c0ad550a605e5e3d1e636e75629049ee750fdd06adc
```

The Python checkpoint SHA-256 is:

```text
8f885d59c5c83006ee5acdc788bc1e007822666fc6cd13926052f67a5478aa19
```

## Outstanding validation

Physical Android device testing, broader school/subject validation, and a Play Store release remain outstanding. Screen renders and a successful build do not replace device testing. The [model card](MODEL_CARD.md) describes the evaluation population and limitations.
