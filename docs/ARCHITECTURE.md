# Architecture

El-Thanawiya has two inference paths sharing one trained model. The Flutter path is the deployed Android product; the Python path supports integration and research.

## Flutter product

`forma/lib/main.dart` loads the bundled `assets/course_risk.json`. `lib/domain/risk_engine.dart` constructs the same fourteen numerical features as Python and applies missing-value medians, standardization, missingness indicators, SiLU layers, the grade-margin residual, and probability calibration. Dropout is disabled at inference.

`lib/ui/` contains the overview, course details, course form, first-run profile, loading screen, palettes, and custom surfaces. `lib/data/student_store.dart` persists courses, profile, and theme with `shared_preferences`.

The normal app starts empty. `--dart-define=DEMO=true` enables illustrative inputs for previewing the interface. Profile fields personalize the UI and are not model inputs. The Android release has no Internet permission; debug/profile manifests permit development tooling.

## Python system

| Module | Responsibility |
| --- | --- |
| `features.py` | Grade normalization, dates, assessment cutoffs, missingness, and shared feature definitions |
| `model.py` | Network, preprocessing, checkpoint loading, and CPU inference |
| `predict.py` | Validated student payloads, course predictions, and partial-coverage summaries |
| `serve.py` | Localhost HTTP adapter with explicitly configured browser-origin support |
| `download_data.py` | Checksum-pinned downloads and allowlisted extraction |
| `prepare_data.py` | Source audits, timing policies, snapshots, and identity groups |
| `train.py` | Grouped splits, architecture comparison, calibration, and artifact export |
| `evaluate.py` | Recheck frozen test probabilities and metrics without training |

The local server is a development interface. A hosted service would require authentication, request limits, transport security, and a separate data-handling design.

## Model contract

`forma/tool/export_model.py` exports `academic-risk/model/course_risk.pt` into JSON and writes synthetic parity fixtures. The JSON stores the checkpoint's SHA-256. `tools/check_repository.py` checks that this checksum still matches the distributed checkpoint.

The Dart tests compare 600 numerical inputs against frozen PyTorch probabilities and seven payload fixtures against Python feature handling. Do not edit the checkpoint, JSON, or fixtures independently after a model change.

## Input semantics

- Normalize grades using the declared bounds and direction. A reversed scale changes quality orientation, not the meaning of a displayed mark.
- Use only scores available by `as_of`. Final-exam outcomes cannot become inputs.
- Prefer an explicitly supplied official current grade; otherwise derive a weighted mean of observed assessments.
- Leave schedule coverage and overdue fractions unknown unless the complete non-final schedule is explicitly supplied.
- Return `insufficient_data` when no grade is observed. Never substitute zero.
- Aggregate only predicted courses and display coverage separately.

## Design choices

On-device inference avoids network dependence and keeps entered records local. Explicit grading policies support varied input scales without using a course name as a feature. Separate probability calibration and an application-overridable alert threshold make the classification tradeoff visible. The credit-weighted term score is a prioritization aid rather than a jointly modeled term outcome.
