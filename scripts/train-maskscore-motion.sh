#!/usr/bin/env bash
# MaskScore-Motion head: LoRA + projector over Gemma-4-12B QAT on motion-diffusion
# output ranking. Same precision split.
#
# TODO(motion-kl): define the MotionKL target axis. Motion-diffusion isn't
# autoregressive, so PF/SC/PQ from EditScore's image rubric don't map 1:1.
# Options:
#   - MotionKL: distributional divergence between generated motion and a
#     reference motion at matched frames (per-joint bf16 vs Python ref)
#   - Kinematic-plausibility: joint-limit-violation count + smoothness metrics
#   - Instruction-following: text prompt vs generated motion via a shared
#     motion-text embed (Kimodo's LLM2Vec side already produces this)

set -euo pipefail

: "${HF_TOKEN:?bootstrap must export HF_TOKEN}"
: "${VAST_INSTANCE_ID:?bootstrap must export VAST_INSTANCE_ID}"

BASE=chibifire/gemma-4-12B-it-qat-q4_0-unquantized
DATASET=TODO_motion_kl  # TODO(motion-kl) — operator or motion-domain expert names
OUT_REPO=chibifire/MaskScore-Motion-Gemma-4-12B-QAT-LoRA
WORK=/workspace/maskscore-motion
mkdir -p "$WORK" && cd "$WORK"

if [ "$DATASET" = "TODO_motion_kl" ]; then
    echo "[maskscore-motion] BLOCKED: TODO(motion-kl) — MotionKL target axis not defined" >&2
    echo "[maskscore-motion] Kimodo's witness (evKimodoSOMA) also hits this gap; solve together" >&2
    exit 2
fi

echo "[maskscore-motion] fetch base + dataset $(date -u +%FT%TZ)"
huggingface-cli login --token "$HF_TOKEN" >/dev/null 2>&1 || true
hf download "$BASE" --local-dir base
hf download --repo-type dataset "$DATASET" --local-dir dataset

python3 <<'PY'
# LoRA + motion-embed projector on Gemma-4-12B; head is MotionKL regression.
raise SystemExit("TODO(peer): implement motion-rerank training loop")
PY

python3 -c "
from huggingface_hub import create_repo, upload_large_folder
create_repo('$OUT_REPO', repo_type='model', exist_ok=True)
"
hf upload-large-folder "$OUT_REPO" ./output --repo-type=model --num-workers=4

cat > /tmp/PROV.md <<EOF
# MaskScore-Motion head — Gemma-4-12B QAT LoRA
- Backbone: $BASE
- Dataset: $DATASET
- MotionKL target: TODO(motion-kl) — see script header
- Training compute: Vast.ai instance $VAST_INSTANCE_ID
- Precision: bf16 master + fp32 Adam + 4-bit nf4 forward
- Training date: $(date -u +%FT%TZ)
EOF
hf upload "$OUT_REPO" /tmp/PROV.md FORK_PROVENANCE.md
echo "[maskscore-motion] done"
