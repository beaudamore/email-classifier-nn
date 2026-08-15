# Email Phishing Classifier Progress

**Last updated:** 2026-08-14
**Hardware:** DGX Spark (GB10, 128 GB unified memory)
**Project root:** `training/email-classifier-nn/`

## Current Status

| Phase | Status | Current artifact |
|---|---|---|
| 1. Data generation | Complete | `notebooks/datagen/email_phishing_datagen.ipynb` and validated Parquet outputs |
| 2. XGBoost/MLP baselines | Notebook implemented and structurally validated; training not executed | `notebooks/training/phase2_xgboost_mlp_baselines.ipynb` |
| 3. Specialized neural model | Not started | None |
| 4. Targeted generated-data hardening | Lifecycle documented; implementation not started | Plan section 4.1 |
| 5. Multi-class and additional modalities | Not started | None |

## Phase 1: Data Generation

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

## Phase 2: XGBoost and MLP Baselines

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

## Next Actions

1. Open the Phase 2 notebook in its container-backed notebook environment.
2. Run the dependency-install cell.
3. Restart the notebook kernel.
4. Run the remaining cells from top to bottom.
5. Review validation selection, real-test metrics, adversarial recall, calibration, and false positives.
6. Verify every expected model and provenance artifact under the fingerprinted output directory.
7. Record the winning baseline and measured results in this progress document.
8. Use the winning Phase 2 metrics as the acceptance bar for Phase 3.
