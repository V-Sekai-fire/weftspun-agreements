#!/usr/bin/env bash
# MaskScore-Mesh head: rerank 3D-mesh outputs (TRELLIS.2 / Pixal3D / VoxHammer)
# on Gemma-4-12B QAT. Same precision split.
#
# TODO(mesh-metric): pick the 3D-similarity metric. Candidates:
#   - Chamfer distance (per-vertex; scale-sensitive)
#   - Voxel-IoU (grid-quantized; loses fine detail)
#   - Per-face normal L2 (angular; scale-invariant)
#   - LPIPS on rendered turntable frames (perceptual; needs deterministic rig)

set -euo pipefail
: "${HF_TOKEN:?bootstrap must export HF_TOKEN}"
: "${VAST_INSTANCE_ID:?bootstrap must export VAST_INSTANCE_ID}"
# Base: chibifire/gemma-4-12B-3d-aware-qat (task #146) — supersedes vanilla
# gemma-4-12B-QAT once #146 lands. Until then, fall back to the vanilla base
# noted below; the vanilla suffices for Text and Audio heads (no 3D dep).
# BASE_3D=chibifire/gemma-4-12B-3d-aware-qat  # activate once task #146 lands
BASE=chibifire/gemma-4-12B-it-qat-q4_0-unquantized  # fallback until #146
DATASET=TODO_mesh_rerank
OUT_REPO=chibifire/MaskScore-Mesh-Gemma-4-12B-QAT-LoRA
WORK=/workspace/maskscore-mesh
mkdir -p "$WORK" && cd "$WORK"

if [ "$DATASET" = "TODO_mesh_rerank" ]; then
    echo "[maskscore-mesh] BLOCKED: TODO(mesh-metric) — 3D-similarity metric not picked" >&2
    exit 2
fi

huggingface-cli login --token "$HF_TOKEN" >/dev/null 2>&1 || true
hf download "$BASE" --local-dir base
hf download --repo-type dataset "$DATASET" --local-dir dataset

python3 <<'PY'
# Gemma-4 sees rendered turntable frames of candidate meshes;
# LoRA + mesh-embed projector; head is per-metric regression.
raise SystemExit("TODO(peer): implement mesh-rerank training loop")
PY

python3 -c "from huggingface_hub import create_repo; create_repo('$OUT_REPO', repo_type='model', exist_ok=True)"
hf upload-large-folder "$OUT_REPO" ./output --repo-type=model --num-workers=4
cat > /tmp/PROV.md <<EOF
# MaskScore-Mesh head — Gemma-4-12B QAT LoRA
- Backbone: $BASE
- Dataset: $DATASET
- Mesh metric: TODO(mesh-metric) — see script header
- Training compute: Vast.ai instance $VAST_INSTANCE_ID
- Training date: $(date -u +%FT%TZ)
EOF
hf upload "$OUT_REPO" /tmp/PROV.md FORK_PROVENANCE.md
echo "[maskscore-mesh] done"
