# Email Phishing Classifier — Specialized NN Training Plan

**Hardware**: DGX Spark (GB10, 128 GB unified memory)
**Project root**: `training/email-classifier-nn/`

The product framing, requirements, and current status are in `OVERVIEW.md`. Implementation status, completed artifacts, and next actions are tracked in `PROGRESS.md`.

---

## 1. Scope (Phase 1)

**Binary classification: phishing/malicious vs. legitimate email.**

- Signals used: email body content, subject, available header fields (sender/receiver/date), URL statistics.
- Explicitly out of scope for phase 1 (candidates for phase-2 specialized models or ensemble add-ons):
  - Attachment analysis
  - Visual/QR phishing
  - Open-ended reasoning / explanation generation (LLM territory)
- Phase 1b (optional, after binary works): light multi-class — phish / BEC / spam / legit. **Caveat (verified)**: the classic public corpora label `1 = phishing/spam` collectively; they do not separate marketing spam from credential phishing. Multi-class requires either per-source label heuristics or newer per-class labeled data.

## 2. Data Strategy

Volume + diversity + recency, with strict leakage control. Same discipline as the PubMed pipelines: cleaning, fingerprint deduplication, quality gates, balanced sampling or weighted loss, and grouped train/val/test splits.

### 2.1 Hugging Face sources (verified 2026-08-14; MeAJOR dropped 2026-08-24)

**All public datasets are acquired exclusively from Hugging Face.** The pipeline does not download from corpus host websites, mirrors, or arbitrary URLs.

| Source | Location | Contents | Notes |
|---|---|---|---|
| **Seven Phishing/Spam Email Datasets** | HF: `puyang2025/seven-phishing-email-datasets` | 203,017 rows; raw `text` + `subject` + `sender`/`receiver`/`date` + `urls` count + `dataset_name` + binary `label` (0=ham, 1=phish/spam) | Unified row-level corpus covering **SpamAssassin (5,805), CEAS-08 (39,154), Enron (29,767), Ling-Spam (2,859), TREC-05 (55,275), TREC-06 (16,400), TREC-07 (53,757)**. No single license is asserted; component licenses apply. One repository file is flagged "unsafe" by the HF scanner because the corpus contains malicious email content. Never open links or attachments from the data. |
| **MeAJOR Corpus** (DROPPED, do not re-add) | HF: `simlab-vs/meajor_cleaned_preprocessed` | 108,685 rows; anonymized `body`, subject and header fields, URLs, attachment metadata, engineered URL features, source, and binary `label` (0=benign, 1=phishing) | GECAD dataset (arXiv 2507.17978), CC-BY-4.0. Covers **TREC-05/06/07, Nazario Phishing Corpus, and Nigerian Fraud**, including the requested Nazario-derived data entirely through Hugging Face. |
| **E-PhishGen** | HF: `pajola/e-phishGen` | Official repository for the AISec 2025 E-PhishGen dataset; 10K–100K size category | MIT license. The dataset card currently says the repository is under construction, so it is recorded but not included in the default reproducible pipeline until its schema and files are stable. |

MeAJOR was used in the v1 build and removed in v2: it contains only anonymized TREC-05/06/07 rows, which the seven-corpus dataset already supplies raw, and the anonymization defeated near-duplicate detection, contaminating 46.5% of the v1 test set. The v1 build was deleted on 2026-10-09. The current pipeline uses the seven-corpus dataset alone. Separate SpamAssassin or Enron HF mirrors are not added because those corpora are already represented in the seven-corpus repository and extra mirrors would add provenance ambiguity without adding a new source family.

### 2.2 Future sources

- **E-PhishGen** — enable the verified HF repository after its official dataset card no longer says it is under construction and its schema has been validated.
- **Adversarial BEC datasets** — no matching Hugging Face dataset was found by exact catalog search on 2026-08-14. Until one is verified, generate adversarial augmentations deterministically (see §2.4).
- **Proprietary labeled data** from Phoenix engagements / customer feedback loops (anonymized). This is the real differentiator — recency + real campaign tactics. Requires an intake + anonymization step; slot into the same normalized schema.

### 2.3 Pipeline (datagen notebook)

`notebooks/datagen/email_phishing_datagen_v2.ipynb`:

1. **Download** — pull `puyang2025/seven-phishing-email-datasets` from Hugging Face into local `data/source-raw/`.
2. **Normalize** — preserve `hf_dataset`, map the source schema to `body, subject, sender, receiver, date, urls, url_count, attachment_count, has_attachments, source, label`.
3. **Quality gates** — drop empty/near-empty bodies, non-parseable rows, label sanity checks.
4. **Deduplication** —
   - Exact: SHA-256 fingerprint of normalized `subject + body`.
   - Near-dup: MinHash LSH over word shingles (quoted replies/forwards in these corpora create heavy near-duplication).
5. **Leakage-safe splits** — 80/10/10 train/val/test, **grouped** so that no sender domain and no near-duplicate cluster spans splits; stratified by label and source where the grouping allows.
6. **Feature engineering** — per-email engineered features for the baseline model: URL stats, header anomalies, lexical/character statistics.
7. **Adversarial augmentation (train split only)** — deterministic obfuscation copies: homoglyph substitution, zero-width character injection, URL obfuscation. Never added to val/test (val/test adversarial evaluation uses a separately generated fixed set).
8. **Verify & save** — class balance, per-source distribution, cross-split leakage checks; write `data/source-clean-v2/{train,val,test,adversarial_test}.parquet` + a dataset manifest (fingerprints, counts, config).

### 2.4 Known data risks (from source cards)

- Temporal shift: classic corpora are historical; modern campaigns differ. Mitigate with E-PhishGen after its HF repository stabilizes, plus proprietary phases.
- `label=1` mixes phishing and generic spam in the classic sources.
- PII present in real corpora (esp. Enron) — handle accordingly; redact before any external sharing.
- Live malicious URLs in the data — never fetch them.

## 3. Model Architecture (start simple, specialize)

**Stage A — strong baseline first** (`notebooks/training/phase2_xgboost_mlp_baselines.ipynb`):
- Train **XGBoost** and a small **PyTorch MLP** as competing baselines over the manifest-controlled engineered features.
- Use training data for parameter fitting, real validation for early stopping/calibration/thresholds/model selection, and locked holdouts only after selection.
- Select one baseline winner unless a later experiment explicitly defines and validates an ensemble.
- Establish the measured quality, calibration, robustness, and latency bar that the specialized NN must beat.

**Stage B — specialized NN**:
- Hybrid: 1D-CNN (local n-gram/style patterns) + Bi-LSTM/GRU (sequence) + dense head; or CNN + XGBoost fusion.
- Alternative: fine-tune a lightweight transformer (DistilBERT-scale or smaller custom) on the email domain only.
- Target: compact nets (hundreds of K params) — deployable on modest hardware, low latency, data-sovereign.

**Not doing**: full LLM backbone for pure detection. Revisit only if the use case later demands open-ended reasoning.

## 4. Training & Evaluation Priorities

- **Metrics**: precision / recall / F1 per class, ROC-AUC, calibration (reliability curves). Optimize for **high phishing recall** at a false-positive rate low enough that analysts trust the tool; report the full precision-recall tradeoff, not a single operating point. Working targets (`OVERVIEW.md` §5): recall ≥ 95% at FPR ≤ 1% for alerting, FPR ≤ 0.1% for automatic actions.
- **Adversarial robustness**: evaluate on the held-out obfuscated set from day one.
- **Continuous evaluation**: hold out the most recent campaigns (or newest-by-date slices) as a temporal test set.
- **Explainability**: feature attribution (SHAP for XGBoost; integrated gradients / attention maps for the NN) so a SOC can see *why* a message was flagged.
- Class weighting or balanced sampling for label skew (per-source balance verified in the datagen notebook).

### 4.1 Phase 4 — Generated Data Lifecycle

Phase 4 does not end when OpenRouter returns examples. Generated data is an input to a controlled retraining experiment for the classifiers built in phases 2 and 3.

#### A. Produce two separate artifacts

1. `data/synthetic/synthetic_train.parquet` — targeted hard examples eligible for training.
2. `data/synthetic/adversarial_eval.parquet` — a fixed challenge set that is **never used for training, threshold selection, or hyperparameter selection**.

Every generated row must include the normalized email fields plus `label`, `attack_type`, `difficulty`, `generation_model`, `prompt_version`, `generated_at`, and `synthetic=true`. Generated URLs and domains must be inert (`.test` or equivalent), not live infrastructure.

#### B. Gate the generated rows

Before any row enters `synthetic_train.parquet`:

- Validate the schema and allowed labels.
- Reject empty, malformed, contradictory, or template-leaking examples.
- Verify that the content actually expresses its declared label and attack type.
- Deduplicate against the real corpus and other generated examples using the same exact and near-duplicate pipeline as phase 1.
- Record accepted/rejected counts and reasons in a versioned manifest.

Do not modify or regenerate the real `train`, `val`, or `test` files produced in phase 1.

#### C. Build reproducible training mixtures

Create versioned experiment manifests that reference the immutable real training set and an explicitly sampled subset of `synthetic_train.parquet`. Compare:

- **Control**: real training data only.
- **Augmented candidates**: real training data plus several synthetic sampling weights or proportions.

The proportions are selected experimentally; they are not fixed in advance. Synthetic rows receive the same feature engineering and tokenization as real rows. They are appended only at training time, with source/provenance retained so per-source performance can be audited.

#### D. Retrain the actual detector

For every mixture, retrain from the same initialization and configuration:

- Phase-2 XGBoost and MLP baselines consume the augmented engineered-feature table.
- The selected phase-3 CNN/BiLSTM/GRU or lightweight transformer consumes the augmented text/metadata training set.
- This remains supervised binary-classification training. It does **not** produce SFT or DPO LoRAs.

Use the real validation set for model selection, calibration, and decision-threshold selection. Do not tune against `adversarial_eval.parquet`.

#### E. Evaluate and promote or reject

Evaluate each trained candidate against:

1. The untouched real validation set during development.
2. The fixed adversarial evaluation set for robustness reporting.
3. The untouched real test and temporal holdout only after selecting the final candidate.

Promote an augmented model only if it improves the phase-2/3 control on the predefined phishing-recall and false-positive-rate requirements without materially degrading calibration or performance on legitimate email. If no augmented candidate clears those gates, discard the generated training rows and retain the real-data-only model.

The promoted release records the model configuration, real dataset fingerprint, synthetic dataset fingerprint, mixture manifest, threshold, metrics, and generation provenance. Failed mixtures remain experiment records but are not included in the production training dataset.

## 5. Directory Layout

```
training/email-classifier-nn/
  docs/
    PLAN.md                      ← architecture, phases, and acceptance gates
    PROGRESS.md                  ← implementation status and measured results
    PRODUCTION_IMPLEMENTATION_OPTIONS.md
  data/
    source-raw/                  ← Hugging Face source cache
    source-clean-v2/             ← immutable real splits and manifest
    synthetic/                   ← generated training and evaluation artifacts
  notebooks/
    datagen/
      email_phishing_datagen_v2.ipynb
    training/
      phase2_xgboost_mlp_baselines.ipynb
      phase3_text_cnn_bigru_v2.ipynb
    eval/
  models/
    phase2-v2-{fingerprint}/     ← versioned model and provenance artifacts
    phase3-cnn-bigru-v2-{fingerprint}/
```

## 6. Phase Roadmap

| Phase | Deliverable | Exit criterion |
|---|---|---|
| 1 | Clean, deduplicated, leakage-safe real train/validation/test and adversarial evaluation artifacts | Reproducible manifest, accepted quality gates, and no cross-split leakage |
| 2 | Competing XGBoost and MLP baselines with calibration, thresholds, metrics, and versioned artifacts | Select a reproducible baseline using real validation, then report locked real-test and adversarial performance |
| 3 | Specialized CNN+BiLSTM/GRU or lightweight transformer | Beat the selected Phase 2 baseline on predefined quality and robustness gates without unacceptable latency or false positives |
| 4 | Targeted hard-example generation, gating, training mixtures, controlled retraining, and promotion decision | Promote only an augmented model that clears locked real and adversarial gates; otherwise retain the real-data control |
| 5 | Multi-class detection, proprietary-data intake, and attachment/QR models | Ship each extension only with a verified label contract, isolated evaluation set, and deployment acceptance criteria |
