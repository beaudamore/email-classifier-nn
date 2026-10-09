# Overview: what this is, who it is for, and where it stands

**Last updated:** 2026-10-09. Read this first. It is the three-minute version of the repo; every claim links to the document or artifact that backs it.

---

## 1. The problem

Phishing is still the most common way an attacker gets a first foothold in an organisation. Mail platforms ship filters, but those filters are tuned globally, explain nothing, cannot learn from a specific organisation's analysts, and send message content to a third party. Security teams end up with a black box they cannot audit, cannot tune to their own false-alarm budget, and cannot improve with their own feedback.

## 2. The product

A **self-hosted phishing scorer** that an organisation runs on its own hardware. It reads an inbound email, returns a calibrated probability that the message is phishing, and hands that probability to a policy layer the operator controls: log, alert an analyst, tag, move to review, or quarantine. Every decision is logged with the model version, the data fingerprint, and the threshold, so a verdict can be traced and audited later.

Two model families ship from the same pipeline:

| Model | Input | Size | Role |
|---|---|---|---|
| XGBoost on 12 engineered features | URL counts, IP-literal and `@` URLs, HTML tags, upper-case and digit ratios, suspicious words, non-ASCII and zero-width characters, lengths | 11 MB | Cheap, fully explainable baseline and acceptance bar |
| Text CNN + bidirectional GRU | Subject and body, first 384 tokens, 50k-token vocabulary | 6.7 M parameters, 27 MB | Reads the message; the candidate for deployment |

Both run on a CPU. Neither needs a GPU, a hosted API, or an internet connection at inference time.

## 3. Why a small purpose-built model and not an LLM or a vendor filter

- **Cost and latency.** A mail tenant sees millions of messages a day. A 27 MB model scores one in milliseconds on a CPU. An LLM call per message is orders of magnitude more expensive and slower, and the budget is spent on reading, not deciding.
- **Attacker-controlled input.** An email body is text written by the adversary. Feeding it to an instruction-following LLM makes the filter itself a prompt-injection target. A classifier has no instruction channel to hijack.
- **Determinism and auditability.** The same message always gets the same score from the same model version. Feature importance is available for the XGBoost model today; token attribution for the text model is on the roadmap.
- **Data sovereignty.** Mail never leaves the organisation. The model, the data pipeline, and the evaluation are all in this repository and reproducible from a single fingerprinted manifest.
- **Organisation-specific learning.** Analyst dispositions feed a documented retraining path, so the model improves on the organisation's own mail. Vendor filters do not offer this. The product complements the platform filter; it does not replace it.

## 4. What it does, end to end

```
public email corpora (Hugging Face)           inbound mail (production)
        │                                              │
        ▼                                              ▼
 normalise → quality gates → exact + MinHash dedupe → grouped 80/10/10 split
        │  (train-only adversarial variants, fingerprinted manifest)
        ▼
 12 engineered features ──▶ XGBoost / MLP ──┐
 subject + body tokens  ──▶ CNN + BiGRU  ───┤──▶ calibrated probability
                                             │
                                             ▼
                      policy layer: log / alert / tag / review / quarantine
                      decision log: message id, model run, fingerprint, threshold, action
                      feedback path: analyst verdicts → next training build
```

Training discipline, enforced by assertions in the notebooks: `train` fits parameters; `val` alone drives early stopping, calibration, threshold, and model selection; `test` and `adversarial_test` are opened once, after selection is frozen. Every run writes a manifest with the dataset fingerprint, package versions, device, config, and seed. The exact steps are in [PROCESS.md](PROCESS.md).

## 5. Requirements

Working targets, written down so progress can be measured against them. They are to be confirmed with the operator through the false-positive tolerance interview in [EVALUATION.md](EVALUATION.md) section 11.3.

| Tier | Action | Target |
|---|---|---|
| Alert | Notify an analyst | Phishing recall ≥ 95 % at false-positive rate ≤ 1 % |
| Act | Tag, move to review, quarantine | False-positive rate ≤ 0.1 % |
| Adversarial | Obfuscated phishing (homoglyphs, zero-width characters, URL tricks) | Recall within 2 points of clean recall |
| Latency | Score one message, CPU, p95 | ≤ 50 ms |
| Provenance | Every score traceable to a model run and data fingerprint | Required |

## 6. Where it stands (2026-10-09)

Measured on the locked v2 test split, 16,116 emails, after selecting on validation. Full tables are in the [README](../README.md); per-model detail is in the [model card](MODEL_CARD.md).

| Model | Recall | FPR | F1 | ROC-AUC | Adversarial recall |
|---|---:|---:|---:|---:|---:|
| XGBoost, 12 features | 80.9 % | 16.1 % | 0.810 | 0.902 | 99.9 % |
| CNN + BiGRU, text | 95.8 % | 15.3 % | 0.897 | 0.971 | 99.7 % |

**Plain reading.** The text model clears the Phase 2 bar on recall by 15 points and on F1 by 9 points at a similar false-positive rate, so Phase 3 is the candidate. It meets the alert-tier recall target. It does **not** meet the alert-tier FPR target: 15 % is fifteen times the budget. Neither model is deployable as an automatic enforcer today. The product is at the stage where the pipeline, the evaluation protocol, and the model architecture are proven, and the operating point is not.

**The validation-to-test gap, explained.** The text model's validation FPR was 1.8 %; its test FPR is 15.3 %. Slicing the test false positives by sender domain located the cause: three legitimate bulk-mail domains from TREC-07 (stock-quote notifications, CNN newsletters, cbsig.com), held out entirely in test by the domain-grouped split, account for 89 % of them. Without those three domains the test FPR is 2.1 %, matching validation. The test number is still the number, because unseen bulk senders are a real production risk, but it is one draw of the split, and the uncertainty lives at the domain level: a domain-level bootstrap and several split seeds are the next evaluation step, and sender allow-listing in the policy layer is the product answer. Details in the README results section.

## 7. The lesson this repo is built around

The first data build merged two public corpora. One of them, MeAJOR, turned out to be an anonymised re-release of the TREC 05/06/07 corpora that the other already contained raw. Anonymisation changed enough text to defeat near-duplicate detection, so the same emails landed in train and test: **46.5 % of the test set had a twin in train**, and the text model reported F1 0.988. The contamination was measured, the source was dropped, a residual-overlap indicator (subject-twin rate) was added to the manifest, and every model was retrained. The retired build and its models were deleted so nothing in the repo can be trained or reported against them. The honest number for the same architecture on clean data is F1 0.897.

That sequence, detect, measure, fix, re-measure, delete the bad artifacts, is the standard every later build is held to. See [EVALUATION.md](EVALUATION.md) section 1.

## 8. Limitations

- **Historical corpora.** SpamAssassin, Enron, Ling-Spam, CEAS-08, and TREC 05/06/07 are 2003 to 2008 mail. Modern campaigns differ. Recency comes from the proprietary-intake phase, not from these sources.
- **Spam and phishing share a label.** The classic corpora mark both as positive. Separating credential phishing from marketing spam is Phase 5.
- **Text only.** No attachment, image, or QR analysis. Headers beyond sender, receiver, and date are not used.
- **English only.** Vocabulary and suspicious-word list are English.
- **Residual overlap.** Subject-twin rate is 0.35 (val) and 0.30 (test); classic spam corpora repeat subjects heavily. It is tracked, not hidden.
- **Single seed, no confidence intervals yet.** Bootstrap CIs and multi-seed runs are the top of the evaluation backlog.
- **Not deployed.** The serving path (shared feature library, inference service, policy layer) is designed in [PRODUCTION_IMPLEMENTATION_OPTIONS.md](PRODUCTION_IMPLEMENTATION_OPTIONS.md) and not yet built.

## 9. Roadmap

1. Explain the validation-to-test gap with per-corpus and per-domain slices; fix the split or the selection procedure if that is the cause.
2. Bootstrap confidence intervals, recall at fixed FPR (1 %, 0.1 %), and calibration error on every reported number.
3. Choose the operating point from an FPR budget, not F1.
4. Offline serving harness: shared feature library, model loader, parity test against the notebooks, latency measurement.
5. Phase 4: targeted generated hard examples with a gated, versioned intake and a control-versus-augmented retraining experiment.
6. Phase 5: proprietary mail intake with anonymisation, multi-class labels, attachment and QR models.
7. Shadow-mode pilot through Microsoft Graph on consenting mailboxes; analyst feedback loop; drift monitoring.

## 10. Reading order

| Want to | Read |
|---|---|
| See the numbers | [README](../README.md), [MODEL_CARD.md](MODEL_CARD.md) |
| Run it | [PROCESS.md](PROCESS.md) |
| Understand the design choices | [PLAN.md](PLAN.md) |
| Audit the evaluation | [EVALUATION.md](EVALUATION.md) |
| Deploy it into Outlook or Exchange | [PRODUCTION_IMPLEMENTATION_OPTIONS.md](PRODUCTION_IMPLEMENTATION_OPTIONS.md) |
| See what changed when | [PROGRESS.md](PROGRESS.md) |
