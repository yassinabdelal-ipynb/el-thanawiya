# Contributing

Bug reports, reproducibility improvements, accessibility work, and documented validation are welcome. Open an issue describing the problem before proposing a large behavior or model change.

## Local development

Use Flutter 3.47.6 / Dart 3.13.5 for the app and Python 3.10–3.12 for the pinned scientific stack. Follow the component READMEs for setup, then run:

```sh
cd forma
flutter pub get
flutter analyze
flutter test
cd ../academic-risk
python -m unittest discover -s tests -v
cd ..
python tools/check_repository.py
```

Use a branch, keep changes focused, and describe observable before/after behavior in a pull request. Include screenshots for UI changes and relevant check results. Keep discussion respectful and specific.

## Model and feature changes

Preserve date cutoffs, grouped student partitions, explicit missingness, and the distinction between risk and credit-weighted term priority. Never select architecture or tune a threshold against the inspected test set. Document a changed input contract in both runtimes and update parity fixtures through `forma/tool/export_model.py`.

Keep code changes separate from deliberately retrained model artifacts. Record data provenance, licenses, checksums, split policies, and population limits for a new model.

## Data and secrets

Use invented examples in bug reports. Do not submit private student records, API tokens, signing keys, `.env` files, toolchain caches, or build outputs. Raw data and processed research tables should be downloaded/recreated locally, not committed. Follow [SECURITY.md](SECURITY.md) for vulnerabilities.
