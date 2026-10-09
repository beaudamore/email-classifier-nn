# Email Phishing Classifier — End-to-End Process

**Last updated:** 2026-10-09
**Audience:** anyone running or extending this repo, on the DGX Spark or on their own machine.
**Companion docs:** `PLAN.md` (why and what), `PROGRESS.md` (implementation log, stale after 2026-08-14), `../README.md` (current results and status).

This document is the *how*: the order of operations, what each step produces, where it runs, and how work moves between machines without losing anything.

---

## 1. The pipeline in one picture

```
Hugging Face corpus
      │
      ▼
[Phase 1] notebooks/datagen/email_phishing_datagen_v2.ipynb
      │   normalize → quality gates → exact + MinHash dedupe → grouped 80/10/10 split
      │   → 12 engineered features → adversarial variants (train only) → manifest
      ▼
data/source-clean-v2/{train,val,test,adversarial_test}.parquet + manifest.json
      │
      ├──▶ [Phase 2] notebooks/training/phase2_xgboost_mlp_baselines.ipynb
      │         XGBoost + small MLP on the 12 features → models/phase2-v2-<fp>/
      │
      └──▶ [Phase 3] notebooks/training/phase3_text_cnn_bigru_v2.ipynb
                text CNN + BiGRU on subject+body → models/phase3-cnn-bigru-v2-<fp>/
```

`<fp>` is the first 16 characters of the Phase 1 config fingerprint. Every training run records the fingerprint of the data it consumed, so a model can always be traced to the exact dataset build.

---

## 2. Data versions

| Version | Directory | Sources | Status |
|---|---|---|---|
| v1 | `data/source-clean/` | seven-corpus + MeAJOR | **Contaminated** (46.5% test overlap). Frozen. Never retrain against it. |
| v2 | `data/source-clean-v2/` | seven-corpus only | Current. All new runs use this. |

Why v1 failed: MeAJOR is an anonymized re-release of TREC 05/06/07, which the seven-corpus dataset already contains raw. The anonymization changed enough text to defeat near-duplicate detection, so the same emails landed in both train and test. The v2 datagen notebook drops MeAJOR and records a subject-twin rate per split so residual overlap stays visible.

The v1 notebooks and the v1 model directories are kept for the record only. Results measured on v1 are upper bounds, not real generalization.

---

## 3. Where it runs

All three v2 notebooks resolve their project root and compute device at startup and need no edits between machines.

**Project root** is found in this order:

1. `EMAIL_NN_DIR` environment variable, if set.
2. `/workspace/training/email-classifier-nn` (DGX Spark, inside the `unsloth-notebook` container).
3. `/home/spark/projects/training/email-classifier-nn` (DGX Spark host).
4. Walk up from the notebook's working directory until a folder containing `docs/PLAN.md` and `notebooks/` is found. This is what makes a plain clone work anywhere.

**Compute device** is chosen as CUDA, then Apple MPS, then CPU. BF16 autocast is enabled on CUDA only. XGBoost uses CUDA when present and CPU otherwise; it has no MPS backend.

| Machine | Role | Notes |
|---|---|---|
| DGX Spark (GB10, 128 GB unified) | Primary. Runs everything. | JupyterLab in the `unsloth-notebook` container, host port 8889. Data and models live here. The notebooks cap CUDA at 55% of device memory so they coexist with vLLM. |
| Apple Silicon Mac | Optional fallback for the public repo. | Phase 3 runs on MPS. MPS is not bit-for-bit deterministic, so a Mac run and a Spark run differ slightly. Both record their device in the run manifest. |
| Any CPU box | Works, slowly for Phase 3. | Phase 1 and 2 are fine on CPU. Phase 3 is roughly 15 to 35 minutes per epoch on a modern laptop CPU. |

Rough runtime on the Spark: Phase 1 under 30 minutes (first run downloads the corpus), Phase 2 a few minutes, Phase 3 a few minutes per epoch with early stopping around epoch 3 to 7.

---

## 4. Running a full v2 cycle

Run the notebooks top to bottom in this order. Each one checks the manifest and fingerprint of its input before doing any work and will stop with a clear assertion if the previous step is missing.

### Phase 1: build the data

1. Open `notebooks/datagen/email_phishing_datagen_v2.ipynb`.
2. Run all cells. The first run pulls `puyang2025/seven-phishing-email-datasets` from Hugging Face into `data/source-raw/`.
3. Confirm the final cell prints leakage checks passed and the subject-twin rates for val and test.
4. Confirm `data/source-clean-v2/manifest.json` exists and its counts match the printed table.

Never fetch URLs found in the data. The corpus contains live malicious links.

### Phase 2: baselines

1. Open `notebooks/training/phase2_xgboost_mlp_baselines.ipynb`.
2. Run the dependency-install cell once per fresh container, then restart the kernel.
3. Run the remaining cells. The notebook trains XGBoost and the MLP, calibrates both on real validation only, selects thresholds by validation F1, then opens the locked test and adversarial sets.
4. Output lands in `models/phase2-v2-<fp>/` with `metrics.json`, `thresholds.json`, `run_manifest.json`, both model files, scalers, calibrators, and plots.

The selected Phase 2 winner is the acceptance bar Phase 3 must beat.

### Phase 3: text model

1. Open `notebooks/training/phase3_text_cnn_bigru_v2.ipynb`.
2. Run all cells. The vocabulary is built from train only. Model selection uses validation log loss with early stopping. Test and adversarial sets are opened once, after selection.
3. Output lands in `models/phase3-cnn-bigru-v2-<fp>/` with `model_state.pt`, `vocab.json`, `metrics.json`, and `training_history.json`.

### After a run

1. Compare Phase 3 test metrics against the Phase 2 winner. The gates are phishing recall and false-positive rate first, then calibration, per `PLAN.md` section 4.
2. Replace the results tables in `../README.md` with the v2 numbers and note the device and date.
3. Update `PROGRESS.md` with the measured results. It is the implementation log and currently predates every training run.
4. Commit the executed notebooks from the machine that ran them, so the outputs in the repo match the artifacts on disk.

---

## 5. What is in git and what is not

Tracked: notebooks, docs, README, `.gitignore`.

Not tracked, by design: `data/`, `models/`, checkpoints, logs, environments. These exist only on the machine that produced them. The DGX Spark holds the canonical copies. Anyone cloning the repo rebuilds `data/` by running Phase 1.

The executed notebooks are committed *with* their outputs. That is deliberate: the outputs are the only record of a run that travels with the repo.

---

## 6. Working across machines

The repo is edited on more than one machine. GitHub is the hub; each machine is a disposable checkout. Rules that keep the copies from diverging:

- Pull before editing anything. Push when done.
- Never hold unpushed edits to this repo on two machines at once.
- Edit docs and notebook code anywhere. Execute notebooks on the Spark (or the Mac). Commit executed notebooks from the machine that ran them.
- If a checkout is stale and has no local work worth keeping, reset it to GitHub rather than merging. Check `git status` first.

The notebooks' hard-coded Spark paths are a convenience, not a requirement. Set `EMAIL_NN_DIR` or rely on the walk-up resolver on any other machine.

---

## 7. Adding a new data version

When the data pipeline changes in a way that alters the splits:

1. Copy the current datagen notebook to a new version suffix and bump `DATASET_VERSION` in its configuration cell. The old version's output directory stays frozen.
2. Bump `DATASET_VERSION` in the training notebooks, or copy them to new version suffixes if the model also changes.
3. Add the new version to the table in section 2 of this document and to the README.
4. Record why the previous version was retired. The v1 contamination note above is the model for that.

---

## 8. Roadmap pointer

Phases 4 and 5 (targeted generated-data hardening, multi-class and additional modalities) are specified in `PLAN.md` sections 4.1 and 6. Neither has started. The immediate open task is the v2 run of Phases 2 and 3 and the README results update.
