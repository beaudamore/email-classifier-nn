# Email Phishing Classifier — Specialized Neural Network

A binary phishing-versus-legitimate email classifier built without an LLM: a Hugging Face
data pipeline with leakage-safe splits and adversarial augmentation, XGBoost and MLP baselines
on twelve engineered features, and a text CNN + bidirectional GRU that reads the message
itself. Trained on an NVIDIA DGX Spark.

The most important result in this repo is a negative one: the first dataset build was found
to be contaminated, the contamination was measured, and the pipeline was rebuilt.

---

## What it demonstrates

| Area | Specifics |
| --- | --- |
| **Data pipeline** | Two public corpora pulled only from Hugging Face, schema-normalized, quality-gated, exact- and near-duplicate deduplicated (MinHash), split with grouping so near-duplicates never straddle train and test, plus deterministic adversarial phishing variants added to train only. Every build is fingerprinted and described by a manifest. |
| **Leakage detection** | The v1 build merged `puyang2025/seven-phishing-email-datasets` with `simlab-vs/meajor_cleaned_preprocessed`. MeAJOR is an anonymized re-release of TREC 05/06/07, which are already in the first corpus raw; the anonymization defeated near-duplicate detection and produced **46.5% test contamination**. v2 drops MeAJOR and records a subject-twin rate per split so residual overlap is visible. |
| **Baselines before complexity** | Phase 2 trains XGBoost (CUDA `hist`, early stopping) and a small PyTorch MLP on the twelve features, calibrates each on real validation only, picks thresholds by validation F1, and only then opens the locked test and adversarial sets. |
| **Text model** | Phase 3 CNN + BiGRU over a train-only vocabulary (50k tokens, 384-token messages), selected on validation, evaluated on locked holdouts, artifacts versioned by the data fingerprint. |
| **Production thinking** | `docs/PRODUCTION_IMPLEMENTATION_OPTIONS.md` separates Microsoft-provided integration points (Graph, Outlook add-ins, mail-flow rules, gateways) from the custom inference service, policy layer, decision log, feedback path and monitoring. |

---

## Data

### v2 build (current, 2026-08-24, single source)

Source: `puyang2025/seven-phishing-email-datasets` (SpamAssassin, CEAS-08, Enron, Ling-Spam, TREC 05/06/07).

| Split | Rows | Phishing | Legitimate | Augmented |
| --- | ---: | ---: | ---: | ---: |
| train | 137,881 | 68,671 | 69,210 | 8,957 |
| val | 16,116 | 7,464 | 8,652 | 0 |
| test | 16,116 | 7,465 | 8,651 | 0 |
| adversarial_test | 7,465 | 7,465 | 0 | 7,465 |

Recorded caveat: subject-twin rate (share of val/test rows whose subject also appears in train)
is 0.35 for val and 0.30 for test. Classic spam corpora repeat subjects heavily, so this is
tracked in the manifest rather than hidden.

### v1 build (2026-08-14, two sources, contaminated)

278k-row merge of the seven-corpus dataset and MeAJOR (225,225 train / 26,414 val / 26,414 test). Retained only because the Phase 2 and
Phase 3 results below were measured on it.

---

## Results

All artifacts on disk were trained on the **v1 splits** (fingerprint `a1e06b36…`), before the
contamination was found. Treat the numbers as upper bounds, not as the model's true
generalization. The v2 notebooks exist; the v2 runs have not been executed yet.

### Phase 2 baselines on 12 features (2026-08-15, v1 test split)

| Model | F1 | Precision | Recall | ROC-AUC | FPR | Adversarial recall |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| XGBoost (selected) | 0.807 | 0.779 | 0.838 | 0.881 | 26.2% | 99.99% |
| MLP 12→64→32→1 | 0.774 | 0.763 | 0.784 | 0.840 | 26.9% | 99.99% |

Features: body and subject length, URL count, IP-literal and `@` URLs, upper-case and digit
ratios, exclamation count, HTML tags, suspicious-word hits, non-ASCII ratio, zero-width characters.

### Phase 3 text model, CNN + BiGRU (2026-08-15, v1 test split)

| Metric | Value |
| --- | ---: |
| F1 | 0.988 |
| Precision / Recall | 0.987 / 0.990 |
| ROC-AUC | 0.999 |
| False-positive rate | 1.46% |
| Adversarial recall | 99.9% |
| Best epoch | 3 of 7 (patience 4) |

Config: 128-d embeddings, 128 CNN channels, 128 GRU hidden, dropout 0.25, batch 512, LR 2e-3.

The jump from 0.81 to 0.99 F1 is what a text model should give over surface features, but the
v1 leakage means the gap is not yet trustworthy. Re-running Phase 3 on v2 is the open task.

---

## Repo layout

```text
email-classifier-nn/
├── README.md
├── CLAUDE.md                                 Handoff context for Claude Code on any machine
├── .claude/skills/                           pipeline-status, notebook-editing
├── docs/
│   ├── PLAN.md                               Scope, data strategy, architecture, phase roadmap
│   ├── PROCESS.md                            How to run it, per machine, and the cross-machine git rules
│   ├── EVALUATION.md                         Verification protocol: leakage audit, metrics, CIs, robustness, human review
│   ├── PROGRESS.md                           Implementation log
│   └── PRODUCTION_IMPLEMENTATION_OPTIONS.md  Outlook / Exchange deployment options and selection criteria
├── notebooks/
│   ├── datagen/
│   │   ├── email_phishing_datagen.ipynb      v1: two sources (contaminated, kept for the record)
│   │   └── email_phishing_datagen_v2.ipynb   v2: single source, MinHash dedupe, subject-twin audit
│   └── training/
│       ├── phase2_xgboost_mlp_baselines.ipynb
│       ├── phase3_text_cnn_bigru.ipynb       Produced the Phase 3 result above (v1 data)
│       └── phase3_text_cnn_bigru_v2.ipynb    Same model on v2 splits; not yet run
│   (all v2 notebooks run on CUDA, Apple MPS, or CPU without edits)
├── data/                                     (gitignored)
│   ├── source-raw/*.parquet                  Raw HF pulls
│   ├── source-clean/                         v1 splits + manifest
│   └── source-clean-v2/                      v2 splits + manifest
└── models/                                   (gitignored)
    ├── v1-phase2-a1e06b36c0af0662/           xgboost.json, mlp_state.pt, scalers, calibrators,
    │                                         thresholds.json, metrics.json, run_manifest.json, plots
    └── phase3-cnn-bigru-a1e06b36c0af0662/    model_state.pt, vocab.json, metrics.json, training_history.json
```

---

## Running it

Notebooks run in JupyterLab inside the `unsloth-notebook` container (host port 8889); the
GPU is used by XGBoost (`device="cuda"`) and PyTorch.

```text
1. notebooks/datagen/email_phishing_datagen_v2.ipynb     -> data/source-clean-v2/{train,val,test,adversarial_test}.parquet + manifest.json
2. notebooks/training/phase2_xgboost_mlp_baselines.ipynb  -> models/phase2-v2-<fingerprint>/
3. notebooks/training/phase3_text_cnn_bigru_v2.ipynb      -> models/phase3-cnn-bigru-<fingerprint>/
```

Each training notebook verifies the data manifest and fingerprint before it trains, and opens
the test and adversarial sets only after model selection.

---

## Status (2026-10-09)

- Phase 1 complete twice (v1 then v2).
- Phase 2 and Phase 3 trained on v1 with the results above.
- 2026-10-09: Phase 2 notebook switched to v2; all v2 notebooks run on CUDA, MPS, or CPU; `docs/PROCESS.md`, `docs/EVALUATION.md`, and `CLAUDE.md` added. Sibling repo [prompt-injection-nn](https://github.com/beaudamore/prompt-injection-nn) scaffolded on the same process.
- Next: run Phase 2 and Phase 3 on the v2 splits and replace the results table; then Phase 4
  (targeted generated-data hardening) and Phase 5 (multi-class: phish / BEC / spam / legit) as
  laid out in `docs/PLAN.md`.
