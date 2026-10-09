# Model Card: email phishing classifiers, v2 data build

**Models:** `phase2-v2-72487aa3531fde58` (XGBoost, selected Phase 2 baseline) and `phase3-cnn-bigru-v2-72487aa3531fde58` (text CNN + BiGRU, Phase 3 candidate)
**Trained:** 2026-10-09 on an NVIDIA DGX Spark (GB10, CUDA 13.0, PyTorch 2.10, XGBoost 3.4.0)
**Data fingerprint:** `72487aa3531fde58314e1cdfbe8e8b528d95cd0bceeb5c0ad8369dd6e0fdf450`
**Status:** research candidates. Not deployed. See [OVERVIEW.md](OVERVIEW.md) section 6.

## Intended use

Score inbound email for phishing likelihood inside an organisation's own infrastructure, feeding a policy layer that decides whether to log, alert, tag, or quarantine. Intended operators are security teams or mail administrators who can set a false-positive budget and review flagged mail.

## Out of scope

- Automatic deletion or rejection of mail at the current false-positive rate.
- Mail in languages other than English.
- Attachment, image, or QR-code based phishing.
- Distinguishing credential phishing from marketing spam (the training labels merge them).
- Any use where the message content is not available in plain text (encrypted or rights-managed mail).

## Training data

Source: `puyang2025/seven-phishing-email-datasets` on Hugging Face, covering SpamAssassin, CEAS-08, Enron, Ling-Spam, and TREC 05/06/07 (2003 to 2008 mail). Pipeline: schema normalisation, minimum body length 20 characters, SHA-256 exact dedupe, MinHash LSH near-dedupe (5-word shingles, Jaccard 0.90, 128 permutations), 80/10/10 split grouped by near-duplicate cluster and sender domain and balanced by label and source corpus, deterministic adversarial variants (homoglyphs, zero-width characters, URL obfuscation) added to train only.

| Split | Rows | Phishing | Legitimate | Augmented |
|---|---:|---:|---:|---:|
| train | 137,881 | 68,671 | 69,210 | 8,957 |
| val | 16,116 | 7,464 | 8,652 | 0 |
| test | 16,116 | 7,465 | 8,651 | 0 |
| adversarial_test | 7,465 | 7,465 | 0 | 7,465 |

Known data issues: historical corpora; spam and phishing share the positive label; PII present in Enron; live malicious URLs in the data, never fetched; subject-twin rate 0.35 (val) and 0.30 (test).

## Architectures

**XGBoost.** Binary logistic objective, `hist` tree method, depth 6, learning rate 0.05, subsample and column-sample 0.8, min child weight 2, L2 1.0, up to 5,000 rounds with early stopping on validation log loss (patience 75). Stopped at round 2,035. Sigmoid calibrator fitted on validation; threshold 0.499 chosen by validation F1. Twelve features: body and subject length, URL count, IP-literal URLs, `@` in URLs, upper-case ratio, digit ratio, exclamation count, HTML tag count, suspicious-word hits, non-ASCII ratio, zero-width character count. Model file 11 MB.

**CNN + BiGRU.** 128-d embeddings over a train-only vocabulary of 50,000 tokens (minimum frequency 2), 384-token window over subject + body, one 1-D convolution (128 channels, kernel 3), one bidirectional GRU (128 hidden per direction), dense head 256 → 128 → 1 with dropout 0.25. AdamW, learning rate 2e-3, weight decay 1e-4, batch 512, BF16 autocast, early stopping on validation log loss (patience 4), best epoch 3 of 7. Threshold 0.73 chosen by validation F1 on a 0.01 grid. 6,680,449 parameters, of which 6,400,000 are the embedding table. Model file 27 MB.

## Evaluation

Validation drives selection; test and adversarial sets are opened once afterwards. Single seed (42). No confidence intervals yet.

### Locked test split (16,116 emails, 46.3 % phishing)

| Model | Precision | Recall | F1 | ROC-AUC | Avg precision | FPR | Brier | TN / FP / FN / TP |
|---|---:|---:|---:|---:|---:|---:|---:|---|
| XGBoost | 0.812 | 0.809 | 0.810 | 0.902 | 0.901 | 16.1 % | 0.122 | 7,257 / 1,394 / 1,429 / 6,036 |
| MLP (not selected) | 0.715 | 0.798 | 0.754 | 0.862 | 0.854 | 27.4 % | 0.149 | 6,278 / 2,373 / 1,507 / 5,958 |
| CNN + BiGRU | 0.844 | 0.958 | 0.897 | 0.971 | 0.965 | 15.3 % | 0.092 | 7,327 / 1,324 / 311 / 7,154 |

### Validation split (for reference; selection was done here, so these are optimistic)

| Model | Recall | F1 | FPR |
|---|---:|---:|---:|
| XGBoost | 0.813 | 0.831 | 12.4 % |
| CNN + BiGRU | 0.955 | 0.967 | 1.8 % |

### Adversarial test (7,465 obfuscated phishing emails)

| Model | Recall | Mean probability |
|---|---:|---:|
| XGBoost | 99.9 % | 0.993 |
| CNN + BiGRU | 99.7 % | 0.997 |

The adversarial set is built by perturbing known phishing, so high recall shows the obfuscations do not break detection; it does not show robustness to novel campaigns.

### Operating points chosen on validation (`notebooks/eval/eval_v2_locked_test.ipynb`, 2026-10-09)

Threshold = lowest value whose validation FPR is within budget, then applied once to test. 95 % percentile bootstrap, 1,000 resamples.

| Model | Budget | Threshold | Test recall | Test FPR | FPR interval (rows) | FPR interval (sender domains) | ECE |
|---|---|---:|---:|---:|---:|---:|---:|
| CNN + BiGRU | alert, FPR ≤ 1 % | 0.900 | 93.9 % | 12.8 % | 12.1 to 13.5 % | 1.4 to 25.8 % | 0.086 |
| CNN + BiGRU | act, FPR ≤ 0.1 % | 0.992 | 81.4 % | 5.5 % | 5.0 to 6.0 % | 0.3 to 12.9 % | 0.086 |
| XGBoost | alert, FPR ≤ 1 % | 0.893 | 48.2 % | 1.2 % | 1.0 to 1.5 % | 0.6 to 2.1 % | 0.039 |
| XGBoost | act, FPR ≤ 0.1 % | 0.979 | 24.9 % | 0.6 % | 0.4 to 0.7 % | 0.04 to 1.5 % | 0.039 |
| MLP | alert, FPR ≤ 1 % | 0.865 | 39.7 % | 2.0 % | 1.7 to 2.3 % | 1.0 to 3.6 % | 0.035 |

Recall at FPR with the threshold set on test itself (upper bound): CNN 61.1 / 57.0 / 42.1 % at 1 / 0.5 / 0.1 %; XGBoost 42.5 / 12.9 / 6.0 %.

## Known failure modes and caveats

- **Validation-to-test gap on the text model, located.** FPR 1.8 % on val versus 15.3 % on test. Three TREC-07 bulk-mail sender domains held out entirely in test (broadcast.shareholder.com, mail.cnn.com, cbsig.com) account for 89 % of the test false positives; without them the test FPR is 2.1 %. The gap is split-draw variance at the sender-domain level, not a corpus imbalance or a selection error. Treat the test number as the real one for unseen bulk senders, and treat its uncertainty as domain-level: a domain-level bootstrap and multiple split seeds are required before the FPR is quoted as a single figure. Legitimate bulk mail of this kind is a policy-layer concern (sender allow-listing), not something the body-only model can resolve.
- **False-positive rate is far above budget.** At the F1-optimal threshold both models flag roughly one legitimate email in six or seven. The operating point must be re-chosen from a recall-at-FPR table against a stated budget before any automatic action.
- **Temporal drift.** Training mail predates modern campaigns; expect degraded recall on current lures until proprietary intake adds recent data.
- **Calibration.** Brier 0.092 (text) and 0.122 (XGBoost) on test; reliability diagrams exist for Phase 2; ECE not yet computed.

## Artifacts

- Phase 2: `models/phase2-v2-72487aa3531fde58/` with `xgboost.json`, `xgboost_calibrator.joblib`, `mlp_state.pt`, `mlp_scaler.joblib`, `mlp_calibrator.joblib`, `thresholds.json`, `metrics.json`, `config.json`, `feature_columns.json`, `package_versions.json`, `run_manifest.json`, validation diagnostics and feature-importance plots.
- Phase 3: `models/phase3-cnn-bigru-v2-72487aa3531fde58/` with `model_state.pt`, `vocab.json`, `metrics.json` (includes config, best epoch, and all metrics), `training_history.json`.

Artifacts are not tracked in git; the executed notebooks, committed with outputs, are the portable record of each run.
