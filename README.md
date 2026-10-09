# Email Phishing Classifier

A self-hosted phishing scorer an organisation can run on its own hardware. It reads an inbound
email, returns a calibrated probability that the message is phishing, and hands that to a policy
layer the operator controls: log, alert, tag, review, or quarantine. No LLM, no hosted API, no
mail leaving the building. A 27 MB text model and an 11 MB feature model, both CPU-scorable in
milliseconds, trained from a fingerprinted, leakage-audited data pipeline.

**Start with [docs/OVERVIEW.md](docs/OVERVIEW.md)**: the problem, the product, why a small
purpose-built model instead of an LLM or a vendor filter, the requirements, where it stands,
and the roadmap. Per-model detail is in [docs/MODEL_CARD.md](docs/MODEL_CARD.md).

**Status in one line (2026-10-09):** the pipeline, evaluation protocol, and architecture are
proven on clean data; the text model meets the recall target (95.8 %) but not the false-positive
target (15.3 % against a 1 % budget), so it is a candidate, not a deployable enforcer. The most
important result in the repo is still a negative one: the first data build was contaminated,
the contamination was measured at 46.5 % of the test set, the pipeline was rebuilt, and every
model was retrained.

---

## What it demonstrates

| Area | Specifics |
| --- | --- |
| **Product framing** | A stated user, a stated false-positive budget, a policy layer separate from the model, a decision log, and a feedback path. See `docs/OVERVIEW.md` §2 and §5. |
| **Data pipeline** | A public corpus pulled only from Hugging Face, schema-normalised, quality-gated, exact- and near-duplicate deduplicated (MinHash), split with grouping so near-duplicates and sender domains never straddle train and test, plus deterministic adversarial phishing variants added to train only. Every build is fingerprinted and described by a manifest. |
| **Leakage detection** | The v1 build merged `puyang2025/seven-phishing-email-datasets` with `simlab-vs/meajor_cleaned_preprocessed`. MeAJOR is an anonymised re-release of TREC 05/06/07, which the first corpus already contains raw; the anonymisation defeated near-duplicate detection and produced **46.5 % test contamination**. v2 drops MeAJOR and records a subject-twin rate per split so residual overlap stays visible. The retired build and its models were deleted. |
| **Baselines before complexity** | Phase 2 trains XGBoost and a small PyTorch MLP on twelve engineered features, calibrates each on validation only, picks thresholds by validation F1, and only then opens the locked test and adversarial sets. The winner is the bar Phase 3 must clear. |
| **Text model** | Phase 3 CNN + BiGRU over a train-only vocabulary (50k tokens, 384-token window), selected on validation, evaluated on locked holdouts, artifacts versioned by the data fingerprint. 6.7 M parameters. |
| **Evaluation protocol** | `docs/EVALUATION.md` lists every check a reviewer should expect, with an honest done / partial / open status and a prioritised backlog. |
| **Production design** | `docs/PRODUCTION_IMPLEMENTATION_OPTIONS.md` separates Microsoft-provided integration points (Graph, Outlook add-ins, mail-flow rules, gateways) from the custom inference service, policy layer, decision log, feedback path, and monitoring, with a staged shadow-first rollout. |

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

Each split has the same per-corpus mix. Recorded caveat: subject-twin rate (share of val/test
rows whose subject also appears in train) is 0.35 for val and 0.30 for test. Classic spam
corpora repeat subjects heavily, so this is tracked in the manifest rather than hidden.

### v1 build (2026-08-14, retired)

Merged the seven-corpus dataset with MeAJOR and was found to be contaminated (see the leakage
row above). Its notebook, splits, and models were deleted on 2026-10-09 so nothing in the repo
can be trained or reported against it. The v1 notebooks remain in git history before that date.

---

## Results

All numbers are measured on the **v2 splits** (fingerprint `72487aa3…`) on an NVIDIA DGX Spark
(GB10, CUDA), single seed. Test and adversarial sets were opened once, after selection on
validation. Thresholds maximise validation F1.

### Locked test split (16,116 emails)

| Model | Recall | FPR | Precision | F1 | ROC-AUC | Avg precision | Adversarial recall |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| **CNN + BiGRU, text (Phase 3)** | **95.8 %** | 15.3 % | 0.844 | **0.897** | **0.971** | **0.965** | 99.7 % |
| XGBoost, 12 features (Phase 2, selected) | 80.9 % | 16.1 % | 0.812 | 0.810 | 0.902 | 0.901 | 99.9 % |
| MLP 12→64→32→1 (Phase 2) | 79.8 % | 27.4 % | 0.715 | 0.754 | 0.862 | 0.854 | 99.9 % |

**Reading it.** The text model beats the Phase 2 bar by 15 recall points and 9 F1 points at a
similar false-positive rate, so Phase 3 is the candidate. On the test mix that is 311 missed
phishing emails and 1,324 false alarms out of 16,116. Neither model is inside the 1 % FPR
alert budget; the operating point has to be re-chosen from a recall-at-FPR table, which is
the next evaluation step.

**The validation-to-test gap, explained.** The text model's validation FPR was 1.8 %; on test
it is 15.3 %. Rescoring both splits with the saved model and slicing the false positives by
sender domain located the cause: three bulk-mail domains from TREC-07 that the grouped split
placed entirely in test account for 89 % of the 1,325 false positives.

| Sender domain | Legitimate emails in test | Flagged |
| --- | ---: | ---: |
| broadcast.shareholder.com (stock-quote notifications) | 642 | 574 |
| mail.cnn.com (newsletters) | 780 | 431 |
| cbsig.com | 554 | 177 |

Without those three domains the test FPR is 2.1 %, in line with validation. Per corpus,
TREC-07 is the only outlier (49 % FPR on test, 0.1 % on val); every other corpus is within
a few points of its validation figure. The model flags these with median probability 0.985:
it has never seen the template and reads "Stock Quote Notification" as phishing.

Two conclusions. First, the test number is honest about a real production risk, unseen bulk
senders, but it is one draw of the split: a different seed would hold out different large
domains and give a different FPR. The row-level bootstrap understates this because the
uncertainty sits at the domain level; a domain-level bootstrap and three to five split seeds
are what turn 15.3 % into a defensible range. Second, this class of false positive belongs to
the policy layer (sender allow-listing, sender reputation), not to the text model, which
cannot know from the body alone that a shareholder-services domain is legitimate.

Training details: XGBoost early-stopped at round 2,035 of a 5,000 cap; the MLP's best epoch was
141 of 200; the text model's best epoch was 3 of 7 (patience 4). Full configs, confusion
counts, and calibration scores are in `docs/MODEL_CARD.md`.

Features for the Phase 2 models: body and subject length, URL count, IP-literal and `@` URLs,
upper-case and digit ratios, exclamation count, HTML tags, suspicious-word hits, non-ASCII
ratio, zero-width characters.

---

## Repo layout

```text
email-classifier-nn/
├── README.md
├── CLAUDE.md                                 Handoff context for Claude Code on any machine
├── .claude/skills/                           pipeline-status, notebook-editing
├── docs/
│   ├── OVERVIEW.md                           Start here: problem, product, requirements, status, roadmap
│   ├── MODEL_CARD.md                         Intended use, data, architectures, full metrics, failure modes
│   ├── PLAN.md                               Scope, data strategy, architecture, phase roadmap
│   ├── PROCESS.md                            How to run it, per machine, and the cross-machine git rules
│   ├── EVALUATION.md                         Verification protocol: leakage audit, metrics, CIs, robustness, human review
│   ├── PROGRESS.md                           Implementation log
│   └── PRODUCTION_IMPLEMENTATION_OPTIONS.md  Outlook / Exchange deployment options and selection criteria
├── notebooks/
│   ├── datagen/
│   │   └── email_phishing_datagen_v2.ipynb   Phase 1: single source, MinHash dedupe, grouped balanced split, subject-twin audit
│   └── training/
│       ├── phase2_xgboost_mlp_baselines.ipynb   Phase 2: produced the XGBoost and MLP rows above
│       └── phase3_text_cnn_bigru_v2.ipynb      Phase 3: produced the CNN + BiGRU row above
│   (all notebooks run on CUDA, Apple MPS, or CPU without edits; committed with outputs)
├── data/                                     (gitignored)
│   ├── source-raw/*.parquet                  Raw HF pull
│   └── source-clean-v2/                      v2 splits + manifest
└── models/                                   (gitignored)
    ├── phase2-v2-72487aa3531fde58/           xgboost.json, mlp_state.pt, scalers, calibrators,
    │                                         thresholds.json, metrics.json, run_manifest.json, plots
    └── phase3-cnn-bigru-v2-72487aa3531fde58/ model_state.pt, vocab.json, metrics.json, training_history.json
```

---

## Running it

Notebooks run in JupyterLab (on the reference machine, inside the `unsloth-notebook` container
on host port 8889). They resolve their project root and compute device themselves, so a plain
clone runs on CUDA, Apple MPS, or CPU without edits. Phase 1 pulls the corpus from Hugging Face
on first run.

```text
1. notebooks/datagen/email_phishing_datagen_v2.ipynb     -> data/source-clean-v2/{train,val,test,adversarial_test}.parquet + manifest.json
2. notebooks/training/phase2_xgboost_mlp_baselines.ipynb  -> models/phase2-v2-<fingerprint>/
3. notebooks/training/phase3_text_cnn_bigru_v2.ipynb      -> models/phase3-cnn-bigru-v2-<fingerprint>/
```

Each training notebook verifies the data manifest and fingerprint before it trains, and opens
the test and adversarial sets only after model selection. Step-by-step instructions, runtimes,
and the cross-machine rules are in `docs/PROCESS.md`.

The data contains live malicious URLs. Never fetch them.

---

## Roadmap

1. Explain the validation-to-test gap with per-corpus and per-domain slices.
2. Bootstrap confidence intervals, recall at 1 % and 0.1 % FPR, calibration error.
3. Operating point from an FPR budget, not F1.
4. Offline serving harness with a shared feature library and a parity test against the notebooks.
5. Phase 4: gated generated hard examples and a control-versus-augmented retraining experiment.
6. Phase 5: proprietary mail intake, multi-class labels, attachment and QR models.
7. Shadow-mode pilot via Microsoft Graph, analyst feedback loop, drift monitoring.

Sibling repo on the same process: [prompt-injection-nn](https://github.com/beaudamore/prompt-injection-nn).
