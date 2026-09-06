#!/usr/bin/env bash
# Gemma-4-12B 3D-shape vision FT (task #146) — second Vast workload.
# Consumes the Mitsuba corpus from task #147. Fine-tunes Gemma-4-12B's
# vision head + adapter on multi-view 3D-shape understanding. QAFT-4bit
# per 4bit-qaft-is-default doctrine.
#
# Output: chibifire/gemma-4-12B-3d-aware-qat — supersedes vanilla
# Gemma-4-12B QAT as the MaskScore backbone.

set -euo pipefail
: "${HF_TOKEN:?bootstrap must export HF_TOKEN}"
: "${VAST_INSTANCE_ID:?bootstrap must export VAST_INSTANCE_ID}"

BASE=chibifire/gemma-4-12B-it-qat-q4_0-unquantized
CORPUS=chibifire/mitsuba-hammersley-3d-corpus
OUT_REPO=chibifire/gemma-4-12B-3d-aware-qat
WORK=/workspace/gemma4-3d-ft
mkdir -p "$WORK" && cd "$WORK"

# Gate: corpus must exist first (task #147)
if ! hf api "hf.co/api/datasets/$CORPUS" >/dev/null 2>&1; then
    echo "[gemma4-3d-ft] BLOCKED: task #147 corpus $CORPUS not published yet" >&2
    exit 2
fi

huggingface-cli login --token "$HF_TOKEN" >/dev/null 2>&1 || true
hf download "$BASE" --local-dir base
hf download --repo-type dataset "$CORPUS" --local-dir corpus

python3 <<'PY'
# QAFT training on multi-view 3D targets:
#   - cross-view consistency loss (same shape, different views → same latent)
#   - view synthesis (predict novel view given N seed views)
#   - latent reconstruction (round-trip through the shape encoder)
# Mixture is empirical; start 1:1:1 and tune from held-out
#
# Base: Gemma-4-12B vision head (frozen up to layer K, LoRA on the rest)
# Precision per qaft-precision-split: bf16 master + fp32 Adam + 4-bit forward
# Optimizer: AdamW on LoRA + projector params only
raise SystemExit("TODO(peer): implement 3D-shape vision FT loop")
PY

python3 -c "from huggingface_hub import create_repo; create_repo('$OUT_REPO', repo_type='model', exist_ok=True)"
hf upload-large-folder "$OUT_REPO" ./output --repo-type=model --num-workers=4

cat > /tmp/PROV.md <<EOF
# gemma-4-12B-3d-aware-qat

Supersedes chibifire/gemma-4-12B-it-qat-q4_0-unquantized as the MaskScore
backbone for modalities where 3D-shape reasoning matters (Mesh, Pose,
Blendshape, Depth, Video).

- Vanilla base: $BASE
- Training corpus: $CORPUS (Mitsuba + Hammersley multi-view, task #147)
- Training targets: cross-view consistency + view synthesis + latent reconstruction
- Precision: bf16 master + fp32 Adam + 4-bit nf4 forward
- QAFT-4bit per 4bit-qaft-is-default doctrine
- Training compute: Vast.ai instance $VAST_INSTANCE_ID
- Training date: $(date -u +%FT%TZ)
EOF
hf upload "$OUT_REPO" /tmp/PROV.md FORK_PROVENANCE.md

echo "[gemma4-3d-ft] done — MaskScore heads can now retarget to $OUT_REPO"
