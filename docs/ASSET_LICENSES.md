# Code, model, and asset licenses

| Material | Terms |
| --- | --- |
| Original app and pipeline code, documentation, app branding, and UI renders | MIT; see the root `LICENSE` |
| `academic-risk/model/course_risk.pt` and `forma/assets/course_risk.json` | CC BY 4.0, retaining the UCI/OULAD attribution below |
| Derived model metrics, predictions, split assignments, plots, and research reports | CC BY 4.0, retaining source attribution and documenting transformations |
| `forma/assets/fonts/Manrope.ttf` | SIL Open Font License; full text in `forma/assets/fonts/OFL.txt` |
| SDKs, libraries, and generated framework components | Their respective upstream licenses |

Model and derived-output attribution: El-Thanawiya contributors; Paulo Cortez (2008), UCI Student Performance, DOI 10.24432/C5TG7T; Jakub Kuzilek, Martin Hlosta, and Zdenek Zdrahal, OULAD, DOI 10.24432/C5KK69. The pipeline derives normalized grade features, dated course snapshots, binary failure labels, grouped partitions, a trained neural model, and evaluation outputs. It excludes final-exam/banked scores and OULAD withdrawals and assumes a 14-day OULAD score-release delay.

CC BY 4.0 terms: https://creativecommons.org/licenses/by/4.0/

Raw research datasets are downloaded separately from checksum-pinned sources. Halabja annual grades were audited but excluded from training and redistribution. See `THIRD_PARTY_NOTICES.txt` and `forma/assets/model_sources.json` for retained notices.
