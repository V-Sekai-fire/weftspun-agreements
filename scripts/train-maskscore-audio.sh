#!/usr/bin/env bash
# MaskScore-Audio head: LoRA + projector over Gemma-4-12B QAT on audio-clone
# rerank. Same precision split.
#
# TODO(voice-bolt): blocked on the voice-cloning bolt landing first. Without
# a voice-cloning head on Gemma-4-12B (parallel to OmniGen2's image-gen bolt),
# there's no candidate distribution to rank.

set -euo pipefail

: "${HF_TOKEN:?bootstrap must export HF_TOKEN}"
: "${VAST_INSTANCE_ID:?bootstrap must export VAST_INSTANCE_ID}"

BASE=chibifire/gemma-4-12B-it-qat-q4_0-unquantized
DATASET=TODO_audio_rerank
OUT_REPO=chibifire/MaskScore-Audio-Gemma-4-12B-QAT-LoRA
WORK=/workspace/maskscore-audio
mkdir -p "$WORK" && cd "$WORK"

if [ "$DATASET" = "TODO_audio_rerank" ]; then
    echo "[maskscore-audio] BLOCKED: TODO(voice-bolt) — voice-cloning head not landed" >&2
    echo "[maskscore-audio] instance will self-destroy without running" >&2
    exit 2
fi

echo "[maskscore-audio] fetch base + dataset $(date -u +%FT%TZ)"
huggingface-cli login --token "$HF_TOKEN" >/dev/null 2>&1 || true
hf download "$BASE" --local-dir base
hf download --repo-type dataset "$DATASET" --local-dir dataset

python3 <<'PY'
# LoRA + audio-embed projector on Gemma-4-12B; head ranks audio clones by
# fidelity + speaker consistency + prosody quality.
raise SystemExit("TODO(peer): implement audio-rerank training loop")
PY

python3 -c "
from huggingface_hub import create_repo, upload_large_folder
create_repo('$OUT_REPO', repo_type='model', exist_ok=True)
"
hf upload-large-folder "$OUT_REPO" ./output --repo-type=model --num-workers=4

cat > /tmp/PROV.md <<EOF
# MaskScore-Audio head — Gemma-4-12B QAT LoRA
- Backbone: $BASE
- Dataset: $DATASET
- Training compute: Vast.ai instance $VAST_INSTANCE_ID
- Precision: bf16 master + fp32 Adam + 4-bit nf4 forward
- Head: rerank on fidelity + speaker consistency + prosody
- Training date: $(date -u +%FT%TZ)
EOF
hf upload "$OUT_REPO" /tmp/PROV.md FORK_PROVENANCE.md
echo "[maskscore-audio] done"
