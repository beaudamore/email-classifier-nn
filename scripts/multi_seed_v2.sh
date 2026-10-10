#!/usr/bin/env bash
# Multi-seed split runs (docs/EVALUATION.md section 2). For each seed, executes the v2 datagen,
# Phase 2, Phase 3 and the locked-test eval headless inside the unsloth-notebook container with
# EMAIL_NN_SEED set. Data lands in data/source-clean-v2-seed<N>/, models in models/<phase>-v2-<fp>/
# keyed by that build's own fingerprint, and the executed notebook copies in models/multi-seed/seed<N>/
# so the committed notebooks keep their canonical seed-42 outputs. Summarize with
# notebooks/eval/multi_seed_summary_v2.ipynb.
#
# Usage: scripts/multi_seed_v2.sh [seed ...]      (default: 1 2 3)
set -euo pipefail
cd "$(dirname "$0")/.."
SEEDS=("$@"); [ "${#SEEDS[@]}" -eq 0 ] && SEEDS=(1 2 3)
NOTEBOOKS=(notebooks/datagen/email_phishing_datagen_v2.ipynb notebooks/training/phase2_xgboost_mlp_baselines.ipynb notebooks/training/phase3_text_cnn_bigru_v2.ipynb notebooks/eval/eval_v2_locked_test.ipynb)
for seed in "${SEEDS[@]}"; do
  out="models/multi-seed/seed${seed}"; mkdir -p "$out"
  for nb in "${NOTEBOOKS[@]}"; do
    echo "=== seed $seed: $nb ($(date -u +%H:%M:%SZ))"
    docker exec -e EMAIL_NN_SEED="$seed" -w /workspace/training/email-classifier-nn unsloth-notebook \
      python -m jupyter nbconvert --to notebook --execute --ExecutePreprocessor.timeout=7200 --ExecutePreprocessor.kernel_name=python3 \
      --output-dir "/workspace/training/email-classifier-nn/$out" "$nb" 2>&1 | grep -v "^\[NbConvertApp\] Writing"
  done
done
echo "=== done $(date -u +%H:%M:%SZ)"
