#!/usr/bin/env bash
# MaskScore-Depth head: rerank depth-map candidates (See-Through / metric-depth3d)
# on Gemma-4-12B QAT. Per-pixel L1 + KL divergence on normal fields.

set -euo pipefail
: "${HF_TOKEN:?bootstrap must export HF_TOKEN}"
: "${VAST_INSTANCE_ID:?bootstrap must export VAST_INSTANCE_ID}"
# Base: chibifire/gemma-4-12B-3d-aware-qat (task #146) — supersedes vanilla
# gemma-4-12B-QAT once #146 lands. Until then, fall back to the vanilla base
# noted below; the vanilla suffices for Text and Audio heads (no 3D dep).
# BASE_3D=chibifire/gemma-4-12B-3d-aware-qat  # activate once task #146 lands
BASE=chibifire/gemma-4-12B-it-qat-q4_0-unquantized  # fallback until #146
DATASET=TODO_depth_rerank
OUT_REPO=chibifire/MaskScore-Depth-Gemma-4-12B-QAT-LoRA
WORK=/workspace/maskscore-depth
mkdir -p "$WORK" && cd "$WORK"

if [ "$DATASET" = "TODO_depth_rerank" ]; then
    echo "[maskscore-depth] BLOCKED: TODO(dataset) — depth-candidate rerank corpus" >&2
    echo "[maskscore-depth] note: See-Through checkpoints blocklisted per CLAUDE.md (OpenRAIL++-M underneath); pick a licence-clean depth candidate source" >&2
    exit 2
fi

huggingface-cli login --token "$HF_TOKEN" >/dev/null 2>&1 || true
hf download "$BASE" --local-dir base
hf download --repo-type dataset "$DATASET" --local-dir dataset

python3 <<'PY'
# LoRA + depth-map projector; head is per-pixel L1 + normal-field KL regression.
raise SystemExit("TODO(peer): implement depth-rerank training loop")
PY

python3 -c "from huggingface_hub import create_repo; create_repo('$OUT_REPO', repo_type='model', exist_ok=True)"
hf upload-large-folder "$OUT_REPO" ./output --repo-type=model --num-workers=4
cat > /tmp/PROV.md <<EOF
# MaskScore-Depth head — Gemma-4-12B QAT LoRA
- Backbone: $BASE
- Dataset: $DATASET
- Metric: per-pixel L1 + KL divergence on normal fields
- Training compute: Vast.ai instance $VAST_INSTANCE_ID
- Training date: $(date -u +%FT%TZ)
EOF
hf upload "$OUT_REPO" /tmp/PROV.md FORK_PROVENANCE.md
echo "[maskscore-depth] done"
