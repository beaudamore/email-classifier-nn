# CLAUDE.md — email-classifier-nn

Project context for Claude Code. Read this first on any machine. The user's global rules
(`~/.claude/CLAUDE.md`) take precedence over anything here.

## What this repo is

A binary phishing-vs-legitimate email classifier with no LLM: a fingerprinted Hugging Face data
pipeline, XGBoost and MLP baselines on twelve engineered features, and a text CNN + BiGRU.
Public repo: https://github.com/beaudamore/email-classifier-nn

Sibling repo, same process, different task: https://github.com/beaudamore/prompt-injection-nn

## Where things stand (2026-10-09)

- Phase 1 data: v1 (`data/source-clean/`) is **contaminated** (46.5% test overlap via MeAJOR) and frozen. v2 (`data/source-clean-v2/`) is clean and current.
- Phase 2 and Phase 3 were trained on **v1 only**. The numbers in the README are upper bounds.
- All three v2 notebooks now run unchanged on CUDA, Apple MPS, or CPU. Phase 2 points at v2.
- **Open task:** run Phase 2 and Phase 3 on v2 on the DGX Spark, then replace the README results tables and update `docs/PROGRESS.md`.
- Phases 4 and 5 have not started.

Full detail: `docs/PROCESS.md` (how to run), `docs/PROGRESS.md` (log), `docs/EVALUATION.md` (verification criteria), `docs/PLAN.md` (design).

## Machines

| Machine | Role | Path |
|---|---|---|
| DGX Spark | Primary. Runs training. Holds `data/` and `models/`. | `/home/spark/projects/training/email-classifier-nn` on host, `/workspace/training/email-classifier-nn` in the `unsloth-notebook` container (JupyterLab, host port 8889) |
| Mac (Apple Silicon) | Optional fallback. MPS. | any clone |
| Windows laptop | Docs and notebook editing only. CPU-only torch. | `C:\Source\email-classifier-nn` |

Notebooks resolve the project root themselves (env var `EMAIL_NN_DIR`, then the Spark paths, then a walk-up search for `docs/PLAN.md`). Nothing needs editing between machines.

GitHub is the hub. Pull before editing, push when done, never hold unpushed edits on two machines at once. Commit executed notebooks from the machine that ran them.

## Conventions that matter

- **Never retrain against v1 data.** It exists for the historical record only.
- **Notebooks are committed with outputs.** They are the record of a run. Do not clear outputs.
- **Notebook files use LF line endings and `indent=1` JSON.** Editing them from Windows with Python's default `write_text` produces CRLF and a diff touching every line. Use the `notebook-editing` skill in `.claude/skills/`.
- **Holdout discipline.** `train` fits parameters; `val` alone drives early stopping, calibration, thresholds, and model selection; `test` and `adversarial_test` are opened once, at the end. Any change that breaks this is a bug, not a tuning choice.
- **Every run records provenance.** Dataset fingerprint, package versions, device, config, and seed go in the run manifest. A result without a manifest is not a result.
- **Data contains live malicious URLs.** Never fetch them.
- **Do not commit or push unless the user asks.** State the exact change before making it.

## Skills in this repo

- `.claude/skills/pipeline-status/` — snapshot of git state, data versions, model runs, and notebook execution state. Run this first when resuming.
- `.claude/skills/notebook-editing/` — rules and a helper script for editing `.ipynb` files safely (exact-match replacement, LF endings, compile check).

## Related repos

- `safety` — the prompt-injection and content-safety LoRAs served from the Spark's vLLM stack.
- `openwebui-safety-filters` — the live Open WebUI filters.
- `stoic`, `pubmed`, `biblical` — other training repos that used to live under the archived `training` parent; same notebook conventions.
