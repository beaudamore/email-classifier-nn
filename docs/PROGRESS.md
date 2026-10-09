# Email Phishing Classifier Progress

**Last updated:** 2026-10-09
**Hardware:** DGX Spark (GB10, 128 GB unified memory) primary; Apple Silicon and CPU supported since 2026-10-09
**Project root:** any clone; see `PROCESS.md` §3 for path resolution

## Current Status

| Phase | Status | Current artifact |
|---|---|---|
| 1. Data generation | Complete on v2 (2026-08-24). v1 (2026-08-14) found contaminated, retired and deleted 2026-10-09 | `notebooks/datagen/email_phishing_datagen_v2.ipynb`, `data/source-clean-v2/` |
| 2. XGBoost/MLP baselines | **Run on v2 2026-10-09.** XGBoost selected: test F1 0.810, recall 0.809, FPR 16.1%, adversarial recall 99.9% | `notebooks/training/phase2_xgboost_mlp_baselines.ipynb`, `models/phase2-v2-72487aa3531fde58/` |
| 3. Text CNN + BiGRU | **Run on v2 2026-10-09.** Test F1 0.897, recall 0.958, FPR 15.3%, ROC-AUC 0.971, adversarial recall 99.7%. Beats the Phase 2 bar on recall and F1; FPR far above budget; val 1.8% vs test 15.3% FPR gap explained by three TREC-07 bulk-mail domains held out in test (89% of test FPs) | `notebooks/training/phase3_text_cnn_bigru_v2.ipynb`, `models/phase3-cnn-bigru-v2-72487aa3531fde58/` |
| 4. Generated-data hardening | Lifecycle documented; not started | `PLAN.md` §4.1 |
| 5. Multi-class and modalities | Not started | None |

Measured v2 results are in `../README.md`.

## Log

| Date | Change |
|---|---|
| 2026-08-14 | v1 data build (seven-corpus + MeAJOR). Phase 2 notebook written. This document first written. |
| 2026-08-15 | Phase 2 and Phase 3 trained on v1. XGBoost F1 0.807, CNN+BiGRU F1 0.988 on v1 test. |
| 2026-08-24 | v1 contamination measured at 46.5% of test (MeAJOR is anonymized TREC, defeating near-dup detection). v2 datagen built without MeAJOR; subject-twin rate recorded (0.35 val, 0.30 test). Phase 3 v2 notebook created. |
| 2026-10-06 | README written with the v1 results and the contamination finding. |
| 2026-10-09 | Phase 2 notebook switched to v2 data (`DATASET_VERSION`, run ID `phase2-v2-<fp>`). All three v2 notebooks made machine-independent: project root resolves via env var, Spark paths, or walk-up; device resolves CUDA, MPS, or CPU; Phase 3's hard CUDA assert removed. `PROCESS.md`, `EVALUATION.md`, `CLAUDE.md`, and two Claude Code skills added. Sibling repo `prompt-injection-nn` scaffolded. |
| 2026-10-09 | Phase 2 run on v2 on the Spark (GB10, CUDA). XGBoost selected on validation F1 0.831; locked test F1 0.810 / recall 0.809 / FPR 16.1% / ROC-AUC 0.902; MLP test F1 0.754. Adversarial recall 99.9% for both. First pass hit the 2,000-tree cap without early stopping, so the cap was raised to 5,000 and the run repeated (stopped at round 2,035, metrics unchanged to three decimals). XGBoost prediction moved to CPU to remove the device-mismatch warning; pip root warning silenced; all code cells set to scrolled output. |
| 2026-10-09 | v1 retired and deleted: v1 datagen and Phase 3 notebooks removed from the tree (still in git history), `data/source-clean/`, `data/source-raw/meajor_raw.parquet`, and both v1 model directories removed from disk. Docs updated so nothing references v1 files or reports v1 numbers. |
| 2026-10-09 | Phase 3 run on v2 on the Spark. Best epoch 3 of 7, threshold 0.73 by validation F1. Validation F1 0.967 / FPR 1.8%; locked test F1 0.897 / recall 0.958 / FPR 15.3% / ROC-AUC 0.971; adversarial recall 99.7%. Per-corpus mix confirmed identical across splits, so the val-to-test gap is not a corpus imbalance; cause open. `docs/OVERVIEW.md` and `docs/MODEL_CARD.md` written; README rewritten around the product framing with both v2 results. |
| 2026-10-09 | Val-to-test FPR gap located. Rescored val and test with the saved Phase 3 model on CPU (reproduces metrics.json to three decimals) and sliced false positives by corpus and sender domain. TREC-07 is the only outlier corpus (test FPR 49% vs val 0.1%); three bulk-mail domains held out in test (broadcast.shareholder.com 574 of 642 flagged, mail.cnn.com 431 of 780, cbsig.com 177 of 554) are 89% of the 1,325 test FPs, flagged at median probability 0.985. Excluding them, test FPR is 2.1%. Conclusion: domain-level split variance, not a selection or pipeline error; the FPR needs a domain-level interval and multi-seed splits before it is quoted; legitimate bulk mail is a policy-layer (sender allow-list) concern. README, OVERVIEW, MODEL_CARD and CLAUDE.md updated. |

## Next Actions

1. Commit the executed Phase 2 and Phase 3 notebooks and the doc changes from the Spark.
2. Domain-level (grouped) bootstrap on test FPR and recall, and three to five split seeds, so the FPR is reported as a range rather than one draw (`EVALUATION.md` §2, §4). The 2026-10-09 slice shows the 15.3% test FPR is dominated by three held-out bulk-mail domains.
3. Bootstrap confidence intervals, recall@FPR at 1% and 0.1%, and ECE on every reported number (`EVALUATION.md` §3.2, §3.4, §4).
4. Choose the operating point from the recall@FPR table against the working budget in `OVERVIEW.md` §5.
5. Offline serving harness (`PRODUCTION_IMPLEMENTATION_OPTIONS.md`, Stage 1).
