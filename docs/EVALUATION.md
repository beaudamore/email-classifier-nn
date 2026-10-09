# Evaluation and Verification Protocol

**Last updated:** 2026-10-09
**Scope:** what has to be true, and what has to be measured, before a model from this repo is called good. Written so that a reviewer can check each item against the notebooks and the run manifests.

The final column of each table records whether the repo does this today. "Done" means implemented in the v2 notebooks. "Partial" means implemented with a gap noted. "Open" means not implemented yet. The open items are the backlog, in priority order, in section 10.

---

## 1. Data integrity and leakage audit

Leakage is the failure mode that already bit this project once (v1, 46.5% test contamination). Every data build must pass these checks before a model is trained on it.

| Check | Method | Status |
|---|---|---|
| Exact-duplicate removal | SHA-256 over normalized subject + body; report removed count | Done |
| Near-duplicate grouping | MinHash LSH over 5-word shingles, Jaccard ≥ 0.90, 128 permutations; near-dup clusters never straddle splits | Done |
| Group-aware splitting | Split by near-dup cluster and sender domain, stratified by label and source corpus | Done |
| Cross-split overlap test | Assert zero shared fingerprints and zero shared clusters between any two splits | Done |
| Residual-overlap indicator | Subject-twin rate (share of val/test rows whose normalized subject appears in train) recorded in the manifest; v2: 0.35 val, 0.30 test | Done |
| Source-provenance audit | Per-source row counts per split in the manifest; no source may be present in test but absent from train | Done |
| Label-contract check | Labels in {0,1}; adversarial set all-positive, all-augmented; val/test contain zero augmented rows | Done |
| Reproducible build | Config fingerprint (SHA-256 of the full configuration dict) in the manifest; rebuilding with the same config must yield identical counts and fingerprints | Done |
| Datasheet for the dataset | Source cards, licenses, known biases, PII notes, collection dates, intended use | Partial: covered in PLAN.md §2, not as a standalone datasheet |
| Temporal holdout | Hold out the newest-by-date slice as a drift test | Open: the classic corpora are mostly undated or old |
| Label-noise estimate | Hand-review a stratified sample of 200 rows per class; report disagreement rate | Open |

## 2. Experimental protocol

| Requirement | Method | Status |
|---|---|---|
| Three-way split discipline | `train` fits parameters; `val` drives early stopping, calibration, threshold, and model selection; `test` and `adversarial_test` are predicted once, after selection is frozen | Done |
| Seed control | Fixed seed for NumPy, Python, PyTorch, CUDA, MPS; deterministic cuDNN; deterministic shuffle generator | Done |
| Environment capture | Python, NumPy, pandas, scikit-learn, PyTorch, XGBoost versions, CUDA version, device name in `package_versions.json` | Done |
| Run manifest | Run ID, dataset fingerprint, dataset version, feature order, selection criteria, holdout policy, timestamps | Done |
| Baseline-before-complexity | Phase 2 (XGBoost, MLP) sets the bar; Phase 3 must beat it on the same splits | Done |
| Multi-seed variance | Train each final configuration with 3 to 5 seeds; report mean ± standard deviation of every headline metric | Open |
| Ablations | Phase 3 without the CNN; without the GRU; with 256 vs 384 tokens; with and without adversarial augmentation in train | Open |
| Learning curves | Metrics vs training-set fraction (10%, 25%, 50%, 100%) to show whether more data would help | Open |
| Hyperparameter search | If performed, searched on `val` only, with the search space and the number of trials recorded in the manifest | Partial: conservative fixed configs, no search yet |

## 3. Metrics

### 3.1 Threshold-free

| Metric | Why | Status |
|---|---|---|
| ROC-AUC | Ranking quality, insensitive to class balance | Done |
| Average precision (PR-AUC) | The honest number under class imbalance; preferred headline over ROC-AUC | Done |
| Precision-recall curve plot | Shows the full operating-point tradeoff, not one point | Done |

### 3.2 Threshold-dependent

| Metric | Why | Status |
|---|---|---|
| Precision, recall, F1 for the phishing class | Standard | Done |
| Specificity and false-positive rate | FPR is what analysts feel; it is reported separately, not hidden in accuracy | Done |
| Confusion matrix (TN, FP, FN, TP) | Raw counts for any downstream recomputation | Done |
| Recall at fixed FPR (recall@FPR=1%, recall@FPR=0.1%) | The deployment question: how much phishing is caught at a tolerable false-alarm rate | Open |
| FPR at fixed recall (FPR@recall=95%) | The inverse framing for a recall-first policy | Open |
| Accuracy | Reported but never used as the headline; misleading under imbalance | Partial: not reported, by design |

### 3.3 Operating point selection

Threshold is chosen on `val` to maximize F1, ties broken by higher recall then lower threshold. This is recorded in `thresholds.json`. For deployment, the operating point should instead be chosen from the recall@FPR table against a stated FPR budget. Working budget (`OVERVIEW.md` §5): FPR ≤ 1% for alerts, ≤ 0.1% for automatic actions. At the F1-max threshold the v2 models sit at 15 to 16% test FPR, so this item is now the gating one. Status: F1-max done; FPR-budget selection open.

### 3.4 Calibration

A probability that says 0.9 should be right about 90% of the time. Calibration is what lets a SOC set a threshold they can reason about.

| Metric | Method | Status |
|---|---|---|
| Brier score | Mean squared error of probabilities | Done |
| Log loss | Proper scoring rule, penalizes confident mistakes | Done |
| Reliability diagram | Binned predicted vs observed frequency, plotted | Done |
| Expected calibration error (ECE) and maximum calibration error (MCE) | Scalar summaries of the reliability diagram, 10 or 15 bins | Open |
| Post-hoc calibration | Platt (sigmoid) fitted on `val` only | Done |
| Isotonic alternative | Compare against Platt on `val`; use whichever has lower ECE without overfitting | Open |

### 3.5 Slice-based evaluation

Aggregate metrics hide failure on subpopulations. Report every metric in 3.1 and 3.2 per slice, and report the worst slice. Concrete motivation: the Phase 3 text model has FPR 1.8% on `val` and 15.3% on `test` with identical per-corpus mixes. The sender-domain slice found it: three TREC-07 bulk-mail domains held out in test are 89% of the test false positives (2026-10-09). Aggregate numbers hid a domain-level effect, which is also why the bootstrap in section 4 must resample groups, not rows.

| Slice | Status |
|---|---|
| Per source corpus (SpamAssassin, CEAS-08, Enron, Ling-Spam, TREC-05/06/07) | Open |
| Per body-length bucket (short, medium, long, truncated at 384 tokens) | Open |
| With vs without URLs; with vs without HTML | Open |
| Augmented adversarial vs clean | Done (the adversarial set) |

## 4. Statistical rigor

A point estimate on one test set is not evidence that model A beats model B.

| Requirement | Method | Status |
|---|---|---|
| Confidence intervals on test metrics | Percentile bootstrap, 1,000 resamples of the test set, 95% CI on F1, AP, ROC-AUC, recall, FPR | Open |
| Paired model comparison | Paired bootstrap on the metric difference (same resamples for both models); report the CI of the difference, not two separate CIs | Open |
| Significance on disagreements | McNemar's test on the 2×2 of correct/incorrect per model; report the statistic and p-value | Open |
| AUC comparison | DeLong's test for correlated ROC curves | Open |
| Effect size | Report the absolute metric difference and the number of additional emails caught or falsely flagged per 10,000, not only p-values | Open |
| Multiple comparisons | If many configurations are compared, say so and apply a correction or report it as exploratory | Open |

## 5. Robustness

| Test | Method | Status |
|---|---|---|
| Adversarial obfuscation | Locked set of homoglyph, zero-width, and URL-obfuscated phishing variants; report recall and probability shift | Done |
| Leave-one-corpus-out | Train on six corpora, test on the seventh; measures out-of-distribution generalization | Open |
| Perturbation sensitivity | Random character and whitespace noise at 1%, 5%, 10%; metric degradation curve | Open |
| Input-length stress | Metrics on bodies longer than the 384-token window | Open |
| Label-noise sensitivity | Flip 5% and 10% of training labels; measure test degradation | Open |

## 6. Error analysis

| Practice | Method | Status |
|---|---|---|
| False-negative review | Sample 50 FNs from test; categorize (obfuscation, short body, lookalike legitimate template, label error) | Open |
| False-positive review | Sample 50 FPs; categorize (marketing email, mailing-list digest, forwarded phish report, label error) | Open |
| Hard-example table | Top-20 most confident mistakes with scores, in the run directory | Open |
| Confusion by attack type | Requires an attack-type label; available only on the adversarial set and future generated data | Partial |

## 7. Explainability

| Method | Model | Status |
|---|---|---|
| Feature importance (gain) | XGBoost | Done |
| SHAP values, global and per-example | XGBoost | Open |
| Integrated gradients or saliency over tokens | CNN+BiGRU | Open |
| Sanity check: randomized-model test | Attributions must change when weights are randomized; otherwise the method is not explaining the model | Open |

## 8. Efficiency

Deployment targets modest hardware. Measure, do not assume.

| Measurement | Method | Status |
|---|---|---|
| Parameter count and model size on disk | Reported in the run manifest | Partial: recorded in `MODEL_CARD.md` (6.68 M params / 27 MB text, 11 MB XGBoost), not yet in the manifest |
| Latency | p50 and p95, batch size 1 and 32, CPU and GPU, 1,000 warm requests, reported with hardware | Open |
| Throughput | Emails per second at batch 32 on CPU | Open |
| Peak memory | During inference, CPU and GPU | Open |

## 9. Software verification

| Practice | Method | Status |
|---|---|---|
| Notebook structural validation | JSON parses, all code cells compile with magics neutralized, nbformat version recorded | Done (ad hoc; see `notebook-editing` skill) |
| Input-contract assertions | Every training notebook asserts manifest counts, feature order, label contract, and holdout boundaries before training | Done |
| Unit tests for feature engineering | Pure-function tests on the twelve features with hand-built emails; determinism test | Open |
| Schema tests on Parquet outputs | Column names, dtypes, nullability, enum values | Partial: asserted inline, not as a test suite |
| Golden-metrics regression test | Re-run on v2 must reproduce `metrics.json` within a stated tolerance per metric | Open |
| Notebook smoke test | Execute each notebook on a 1% sample in CI | Open |
| Continuous integration | Lint, unit tests, schema tests, notebook smoke test on every push | Open |

## 10. Reporting and sign-off

Before a model is promoted:

1. Run manifest, metrics, thresholds, package versions, and plots exist in the run directory and reference the dataset fingerprint.
2. Headline table: AP, ROC-AUC, F1, recall, FPR, Brier, ECE, each with a 95% bootstrap CI, on `test` and `adversarial_test`.
3. Recall@FPR table at 1% and 0.1%.
4. Slice table with the worst slice called out.
5. Paired comparison against the previous promoted model: CI of the difference and McNemar p-value.
6. Error-analysis summary with the top failure categories.
7. Latency table.
8. Model card: intended use, training data and its known biases, metrics, limitations, and what the model must not be used for. First version: `MODEL_CARD.md`.
9. A reviewer who did not train the model signs off on items 1 to 8.

### Backlog, in priority order

1. Bootstrap CIs and paired comparison (section 4). Cheapest, highest credibility gain.
2. Recall@FPR table and ECE (sections 3.2, 3.4).
3. Slice evaluation per source corpus (3.5).
4. Multi-seed runs (section 2).
5. Error-analysis tables (section 6).
6. Latency and model-size measurement (section 8).
7. Leave-one-corpus-out (section 5).
8. Unit tests, schema tests, CI (section 9).
9. SHAP and integrated gradients (section 7).
10. Model card and datasheet (sections 1, 10).
11. Annotation guideline, agreement study, and gold set (section 11).

## 11. Human verification

Automated metrics are only as good as the labels and the reviewers behind them. These are the human-in-the-loop steps, who does them, and what they produce.

### 11.1 Label quality audit

| Step | Method | Output | Status |
|---|---|---|---|
| Annotation guideline | A written rubric defining phishing vs legitimate, with the edge cases decided in advance: marketing spam, forwarded phish reports, mailing-list digests, internal security-awareness tests | `docs/ANNOTATION_GUIDELINES.md` | Open |
| Stratified review sample | 200 rows per class per source corpus, drawn with a recorded seed, reviewed blind to the source label | Review sheet with reviewer verdict and confidence | Open |
| Inter-annotator agreement | Two reviewers on the same sample; Cohen's kappa for two raters, Krippendorff's alpha if more; target kappa ≥ 0.8 before the rubric is considered stable | Kappa per corpus | Open |
| Adjudication | Disagreements resolved by a third reviewer or discussion; the decision and reasoning recorded; the rubric updated if a rule was missing | Adjudication log | Open |
| Label-noise estimate | Share of source labels the adjudicated verdict overturned, per corpus; corpora above 5% get a flag in the datasheet and a weighted-loss or relabel decision | Noise table in the manifest | Open |
| Gold set | The adjudicated sample becomes a frozen gold evaluation set, never used for training, reported alongside `test` | `data/gold-v1/` with its own manifest | Open |

### 11.2 Model error review

| Step | Method | Output | Status |
|---|---|---|---|
| Blind error review | Reviewer sees the email and the model's verdict but not the source label; records whether the model or the label is wrong and the failure category | Categorized FN/FP table (section 6) | Open |
| Explanation review | For a sample of flagged emails, reviewer rates whether the token attribution (section 7) points at the actual phishing signal; measures whether explanations are useful, not just present | Attribution usefulness score | Open |
| Calibration sanity | Reviewer samples 20 emails each from the 0.4 to 0.6 and 0.9 to 1.0 probability bands and checks whether the uncertainty matches intuition | Qualitative note in the run directory | Open |

### 11.3 Acceptance testing by the end user

| Step | Method | Output | Status |
|---|---|---|---|
| Analyst acceptance run | A SOC analyst or the mail administrator reviews a week of shadow-mode verdicts and marks each as agree, disagree, or unsure | Agreement rate and the disagree list | Open |
| False-positive tolerance interview | Ask the operator directly what false-alarm rate per day is acceptable; convert to the FPR budget used for operating-point selection (section 3.3) | Recorded FPR budget | Open |
| Red-team session | A tester crafts phishing emails not drawn from the corpora, including current campaign styles, and submits them through the pipeline; recall on this set is reported separately | Red-team set and recall | Open |
| Sign-off | Named reviewer, date, model run ID, and the checklist in section 10 | Sign-off record in the run directory | Open |

### 11.4 Audit trail

Every human decision above is recorded with who, when, which rows, and why, so a later reviewer can trace a verdict back to the rubric. Reviewer identities can be pseudonymous in the public repo; the mapping stays private.

## 12. After deployment

Not yet applicable, recorded so the design accounts for it.

- Shadow mode first: score live mail, log, do not act. Compare against the analyst's verdicts.
- Drift monitoring: population stability index or Kolmogorov-Smirnov on each engineered feature and on the score distribution, weekly; alert on a threshold.
- Feedback loop: analyst overrides become labeled rows with provenance, feeding the Phase 5 proprietary-data intake.
- Canary rollout by mailbox population, with the FPR budget as the rollback trigger.
- Periodic re-evaluation on a fresh temporal holdout.
