# Email Phishing Classifier Progress

**Last updated:** 2026-10-09
**Hardware:** DGX Spark (GB10, 128 GB unified memory) primary; Apple Silicon and CPU supported since 2026-10-09
**Project root:** any clone; see `PROCESS.md` §3 for path resolution

## Current Status

| Phase | Status | Current artifact |
|---|---|---|
| 1. Data generation | Complete twice. v1 (2026-08-14) found contaminated; v2 (2026-08-24) is current | `notebooks/datagen/email_phishing_datagen_v2.ipynb`, `data/source-clean-v2/` |
| 2. XGBoost/MLP baselines | Trained on v1 (2026-08-15). Notebook now points at v2; **v2 run pending** | `notebooks/training/phase2_xgboost_mlp_baselines.ipynb` |
| 3. Text CNN + BiGRU | Trained on v1 (2026-08-15, F1 0.988, not trustworthy). v2 notebook started on the Spark, stopped before training; **v2 run pending** | `notebooks/training/phase3_text_cnn_bigru_v2.ipynb` |
| 4. Generated-data hardening | Lifecycle documented; not started | `PLAN.md` §4.1 |
| 5. Multi-class and modalities | Not started | None |

Measured v1 results are in `../README.md`. They are upper bounds because of the v1 leakage.

## Log

| Date | Change |
|---|---|
| 2026-08-14 | v1 data build (seven-corpus + MeAJOR). Phase 2 notebook written. This document first written. |
| 2026-08-15 | Phase 2 and Phase 3 trained on v1. XGBoost F1 0.807, CNN+BiGRU F1 0.988 on v1 test. |
| 2026-08-24 | v1 contamination measured at 46.5% of test (MeAJOR is anonymized TREC, defeating near-dup detection). v2 datagen built without MeAJOR; subject-twin rate recorded (0.35 val, 0.30 test). Phase 3 v2 notebook created. |
| 2026-10-06 | README written with the v1 results and the contamination finding. |
| 2026-10-09 | Phase 2 notebook switched to v2 data (`DATASET_VERSION`, run ID `phase2-v2-<fp>`). All three v2 notebooks made machine-independent: project root resolves via env var, Spark paths, or walk-up; device resolves CUDA, MPS, or CPU; Phase 3's hard CUDA assert removed. `PROCESS.md`, `EVALUATION.md`, `CLAUDE.md`, and two Claude Code skills added. Sibling repo `prompt-injection-nn` scaffolded. |

## Next Actions

1. On the DGX Spark, run `phase2_xgboost_mlp_baselines.ipynb` top to bottom against v2.
2. Run `phase3_text_cnn_bigru_v2.ipynb` top to bottom.
3. Replace the README results tables with the v2 numbers, device, and date.
4. Work the `EVALUATION.md` backlog, starting with bootstrap confidence intervals, recall@FPR, and ECE.
5. Update this document and commit the executed notebooks from the Spark.

---

The sections below are the v1 implementation record from 2026-08-14. They describe the v1 build and the Phase 2 notebook as first written. Paths and counts refer to v1.

## Phase 1 (v1 build): Data Generation

### Implemented

The Phase 1 notebook downloads both public sources exclusively from Hugging Face, normalizes their schemas, merges them, applies quality gates, removes exact duplicates, groups near-duplicates, creates leakage-safe splits, engineers twelve numeric features, and creates deterministic adversarial phishing variants.

Sources:

- `puyang2025/seven-phishing-email-datasets`
- `simlab-vs/meajor_cleaned_preprocessed`

Phase 1 configuration fingerprint:

```text
a1e06b36c0af066201f29acdcb1c07fd886d1b18db75c77b759c164bb5a09dae
```

### Persisted Outputs

| Artifact | Rows | Phishing | Legitimate | Augmented |
|---|---:|---:|---:|---:|
| `data/source-clean/train.parquet` | 225,225 | 106,654 | 118,571 | 13,911 |
| `data/source-clean/val.parquet` | 26,414 | 13,839 | 12,575 | 0 |
| `data/source-clean/test.parquet` | 26,414 | 13,862 | 12,552 | 0 |
| `data/source-clean/adversarial_test.parquet` | 13,862 | 13,862 | 0 | 13,862 |

`data/source-clean/manifest.json` records source repositories, feature order, configuration fingerprint, and split counts.

### Verified Properties

- Validation and real test contain no augmented rows.
- The adversarial test contains only augmented phishing rows.
- Output counts and class counts match the manifest.
- All twelve manifest-controlled feature columns exist and contain no null values.
- No incomplete temporary output remains.
- The mixed-type `date` serialization failure was fixed by converting `date` to nullable string before Parquet writes.

## Phase 2 (as written for v1): XGBoost and MLP Baselines

### Notebook

`notebooks/training/phase2_xgboost_mlp_baselines.ipynb`

The notebook contains 15 cells. It has not been executed. Its JSON structure and persisted source were validated, every code cell compiles after neutralizing notebook magic, all outputs are empty, and every execution count is null.

### Environment

The notebook installs these verified missing dependencies:

- XGBoost 3.4.0
- matplotlib 3.11.1

The Phase 2 environment already contained pandas, PyArrow, NumPy, scikit-learn, PyTorch, and joblib when the notebook was created.

### Input Contract

The notebook loads the Phase 1 manifest and all four Parquet splits. Before training, it verifies:

- Phase 1 fingerprint and manifest counts.
- Manifest-controlled feature order and exactly twelve features.
- Required columns and non-null feature values.
- Binary labels and class counts.
- Validation and real-test augmentation boundaries.
- The all-positive, all-augmented adversarial-test contract.

Data use is constrained as follows:

- Training data fits model parameters and the MLP scaler.
- Real validation controls early stopping, calibration, thresholds, and model selection.
- Real test and adversarial test are used for prediction only in the final evaluation section.

### XGBoost Implementation

- `XGBClassifier` with binary logistic objective.
- `tree_method="hist"` and `device="cuda"`.
- Validation log loss and constructor-level early stopping with 75 rounds.
- Maximum 2,000 estimators, learning rate 0.05, maximum depth 6.
- Subsample and column-sample ratios of 0.8.
- Conservative explicit baseline parameters; no tuning claim.
- Persisted model target: `xgboost.json`.

### PyTorch MLP Implementation

- Training-only `StandardScaler` over the same twelve features.
- Architecture: `12 -> 64 -> 32 -> 1` with ReLU and 0.15 dropout.
- AdamW optimizer and weighted binary cross-entropy.
- Batch size 4,096, maximum 200 epochs, patience 20, minimum delta `1e-5`.
- Deterministic training shuffle and restored best validation-loss state.
- CUDA when available and BF16 autocast when supported.
- `pin_memory=False` for unified memory.
- A 0.55 per-process CUDA memory fraction and CUDA cache clearing between epochs.
- Persisted targets: `mlp_state.pt`, `mlp_scaler.joblib`, and `mlp_calibrator.joblib`.

### Calibration and Selection

Each candidate receives a sigmoid calibrator fitted only on real-validation predictions. Its threshold maximizes validation F1, with ties resolved by higher recall and then lower threshold.

The notebook selects the winning model by:

1. Higher validation F1.
2. Higher phishing recall.
3. Lower false-positive rate.

Both candidates are retained for comparison; the selected winner is the expected single-model production baseline unless a later experiment explicitly defines an ensemble.

### Evaluation and Reports

Binary validation and real-test metrics:

- Precision, recall, and F1.
- ROC-AUC and average precision.
- Brier score and log loss.
- TN, FP, FN, and TP.
- Specificity and false-positive rate.

The all-positive adversarial test reports phishing recall and probability summaries only. It does not report ROC-AUC, specificity, or false-positive rate.

Plots:

- Validation reliability curves.
- Validation precision-recall curves.
- Validation confusion matrices.
- XGBoost feature importance.

### Planned Phase 2 Outputs

Outputs are versioned under:

```text
models/phase2-{phase1_fingerprint_prefix}/
```

Expected artifacts:

- `xgboost.json`
- `xgboost_calibrator.joblib`
- `mlp_state.pt`
- `mlp_scaler.joblib`
- `mlp_calibrator.joblib`
- `thresholds.json`
- `metrics.json`
- `config.json`
- `feature_columns.json`
- `package_versions.json`
- `run_manifest.json`
- Validation diagnostic and feature-importance plots

These model outputs do not exist until the notebook is executed successfully.

## Documentation Completed

- `docs/PLAN.md` - architecture, phase goals, evaluation gates, and generated-data lifecycle.
- `docs/PRODUCTION_IMPLEMENTATION_OPTIONS.md` - Outlook and Exchange deployment options, selection criteria, and staged rollout.
- `docs/PROGRESS.md` - implementation state, completed artifacts, validation evidence, and next actions.
