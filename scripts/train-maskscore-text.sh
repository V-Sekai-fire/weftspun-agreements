#!/usr/bin/env bash
# MaskScore-Text head: LoRA + projector over Gemma-4-12B QAT on a text-diff /
# instruction-following rerank dataset. Same precision split as -image.
#
# TODO(dataset): operator picks the text-diff rerank source. Candidates:
#   - HumanEval / MBPP with model-generated candidates + human ranking
#   - HuggingFaceH4/ultrafeedback_binarized (instruction-following pairs)
#   - operator's own code-review dataset if one exists in the workspace

set -euo pipefail

: "${HF_TOKEN:?bootstrap must export HF_TOKEN}"
: "${VAST_INSTANCE_ID:?bootstrap must export VAST_INSTANCE_ID}"

BASE=chibifire/gemma-4-12B-it-qat-q4_0-unquantized
DATASET=TODO_dataset  # TODO(dataset) — operator names
OUT_REPO=chibifire/MaskScore-Text-Gemma-4-12B-QAT-LoRA
WORK=/workspace/maskscore-text
mkdir -p "$WORK" && cd "$WORK"

if [ "$DATASET" = "TODO_dataset" ]; then
    echo "[maskscore-text] BLOCKED: TODO(dataset) — operator hasn't picked the text-diff rerank source" >&2
    echo "[maskscore-text] instance will self-destroy without running" >&2
    exit 2
fi

echo "[maskscore-text] fetch base + dataset $(date -u +%FT%TZ)"
huggingface-cli login --token "$HF_TOKEN" >/dev/null 2>&1 || true
hf download "$BASE" --local-dir base
hf download --repo-type dataset "$DATASET" --local-dir dataset

echo "[maskscore-text] launch QAFT training"
python3 <<'PY'
# Same shape as train-maskscore-image.sh's Python skeleton, but text-only
# (no mmproj needed; still LoRA + projector on Gemma-4's shared backbone).
# Head is a pointwise regressor on PF/SC/PQ for the code/text diff.
raise SystemExit("TODO(peer): implement text-rerank training loop")
PY

python3 -c "
from huggingface_hub import create_repo, upload_large_folder
create_repo('$OUT_REPO', repo_type='model', exist_ok=True)
"
hf upload-large-folder "$OUT_REPO" ./output --repo-type=model --num-workers=4

cat > /tmp/PROV.md <<EOF
# MaskScore-Text head — Gemma-4-12B QAT LoRA

- Backbone: $BASE
- Dataset: $DATASET
- Training compute: Vast.ai instance $VAST_INSTANCE_ID
- Precision: bf16 master + fp32 Adam + 4-bit nf4 forward
- Head shape: pointwise PF/SC/PQ regression over text/code diffs
- Training date: $(date -u +%FT%TZ)
EOF
hf upload "$OUT_REPO" /tmp/PROV.md FORK_PROVENANCE.md
echo "[maskscore-text] done"
