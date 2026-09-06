#!/usr/bin/env bash
# MaskScore-Blendshape head (aka MaskScore-FacialAction): rerank facial-blendshape
# outputs (ANNY faceunits01) on Gemma-4-12B QAT. Frame-by-frame blendshape-weight
# L2 vs reference. FACS action-unit vocabulary — Apple's convention name for the
# 52-target set is blocklisted per CLAUDE.md, so this head uses the FACS names.

set -euo pipefail
: "${HF_TOKEN:?bootstrap must export HF_TOKEN}"
: "${VAST_INSTANCE_ID:?bootstrap must export VAST_INSTANCE_ID}"
# Base: chibifire/gemma-4-12B-3d-aware-qat (task #146) — supersedes vanilla
# gemma-4-12B-QAT once #146 lands. Until then, fall back to the vanilla base
# noted below; the vanilla suffices for Text and Audio heads (no 3D dep).
# BASE_3D=chibifire/gemma-4-12B-3d-aware-qat  # activate once task #146 lands
BASE=chibifire/gemma-4-12B-it-qat-q4_0-unquantized  # fallback until #146
DATASET=TODO_blendshape_rerank
OUT_REPO=chibifire/MaskScore-Blendshape-Gemma-4-12B-QAT-LoRA
WORK=/workspace/maskscore-blendshape
mkdir -p "$WORK" && cd "$WORK"

if [ "$DATASET" = "TODO_blendshape_rerank" ]; then
    echo "[maskscore-blendshape] BLOCKED: TODO(dataset) — blendshape rerank corpus" >&2
    echo "[maskscore-blendshape] candidate source: ANNY faceunits01 renders vs reference blendshape drives" >&2
    exit 2
fi

huggingface-cli login --token "$HF_TOKEN" >/dev/null 2>&1 || true
hf download "$BASE" --local-dir base
hf download --repo-type dataset "$DATASET" --local-dir dataset

python3 <<'PY'
# LoRA + face-embed projector; head is per-frame blendshape-weight L2
# with the 52 FACS action-unit targets as the output vector.
raise SystemExit("TODO(peer): implement blendshape-rerank training loop")
PY

python3 -c "from huggingface_hub import create_repo; create_repo('$OUT_REPO', repo_type='model', exist_ok=True)"
hf upload-large-folder "$OUT_REPO" ./output --repo-type=model --num-workers=4
cat > /tmp/PROV.md <<EOF
# MaskScore-Blendshape head — Gemma-4-12B QAT LoRA
- Backbone: $BASE
- Dataset: $DATASET
- Metric: frame-by-frame blendshape-weight L2 (52 FACS action-unit targets)
- Training compute: Vast.ai instance $VAST_INSTANCE_ID
- Training date: $(date -u +%FT%TZ)
EOF
hf upload "$OUT_REPO" /tmp/PROV.md FORK_PROVENANCE.md
echo "[maskscore-blendshape] done"
