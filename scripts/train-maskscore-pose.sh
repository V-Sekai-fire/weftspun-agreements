#!/usr/bin/env bash
# MaskScore-Pose head: rerank candidate pose fits on Gemma-4-12B QAT.
# Radial pose-error metric; sits on top of pose-consensus's raw compare
# (CLAUDE.md's pose-consensus does the point comparison; this ranks
# alternatives when the referee returns multiple plausible fits).

set -euo pipefail
: "${HF_TOKEN:?bootstrap must export HF_TOKEN}"
: "${VAST_INSTANCE_ID:?bootstrap must export VAST_INSTANCE_ID}"
# Base: chibifire/gemma-4-12B-3d-aware-qat (task #146) — supersedes vanilla
# gemma-4-12B-QAT once #146 lands. Until then, fall back to the vanilla base
# noted below; the vanilla suffices for Text and Audio heads (no 3D dep).
# BASE_3D=chibifire/gemma-4-12B-3d-aware-qat  # activate once task #146 lands
BASE=chibifire/gemma-4-12B-it-qat-q4_0-unquantized  # fallback until #146
DATASET=TODO_pose_rerank
OUT_REPO=chibifire/MaskScore-Pose-Gemma-4-12B-QAT-LoRA
WORK=/workspace/maskscore-pose
mkdir -p "$WORK" && cd "$WORK"

if [ "$DATASET" = "TODO_pose_rerank" ]; then
    echo "[maskscore-pose] BLOCKED: TODO(dataset) — need pose-candidate rerank corpus" >&2
    echo "[maskscore-pose] candidate: pose-consensus session outputs where the referee returned ambiguous multi-fit" >&2
    exit 2
fi

huggingface-cli login --token "$HF_TOKEN" >/dev/null 2>&1 || true
hf download "$BASE" --local-dir base
hf download --repo-type dataset "$DATASET" --local-dir dataset

python3 <<'PY'
# LoRA + pose-embed projector; head is radial-pose-error regression.
raise SystemExit("TODO(peer): implement pose-rerank training loop")
PY

python3 -c "from huggingface_hub import create_repo; create_repo('$OUT_REPO', repo_type='model', exist_ok=True)"
hf upload-large-folder "$OUT_REPO" ./output --repo-type=model --num-workers=4
cat > /tmp/PROV.md <<EOF
# MaskScore-Pose head — Gemma-4-12B QAT LoRA
- Backbone: $BASE
- Dataset: $DATASET
- Metric: radial pose-error (per-joint angular distance)
- Training compute: Vast.ai instance $VAST_INSTANCE_ID
- Training date: $(date -u +%FT%TZ)
EOF
hf upload "$OUT_REPO" /tmp/PROV.md FORK_PROVENANCE.md
echo "[maskscore-pose] done"
