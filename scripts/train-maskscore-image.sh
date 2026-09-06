#!/usr/bin/env bash
# MaskScore-Image head: LoRA + projector over chibifire/gemma-4-12B-it-qat-q4_0-unquantized
# on EditReward-Bench. Precision split per qaft-precision-split memory:
# bf16 master + fp32 optimizer + 4-bit quantized forward with straight-through.

set -euo pipefail

: "${HF_TOKEN:?bootstrap must export HF_TOKEN}"
: "${VAST_INSTANCE_ID:?bootstrap must export VAST_INSTANCE_ID}"

BASE=chibifire/gemma-4-12B-it-qat-q4_0-unquantized
DATASET=EditScore/EditReward-Bench
OUT_REPO=chibifire/MaskScore-Image-Gemma-4-12B-QAT-LoRA
WORK=/workspace/maskscore-image
mkdir -p "$WORK" && cd "$WORK"

echo "[maskscore-image] fetch base + dataset $(date -u +%FT%TZ)"
huggingface-cli login --token "$HF_TOKEN" >/dev/null 2>&1 || true
hf download "$BASE" --local-dir base
hf download --repo-type dataset "$DATASET" --local-dir dataset

echo "[maskscore-image] launch QAFT training"
python3 <<'PY'
# QAFT training loop (skeleton — real training code lives in a peer's session
# per operator's separation of concerns; this file names the shape).
#
# Shape per memories:
#   - qaft-precision-split: bf16 master + fp32 Adam + 4-bit forward
#   - qat-4bit-plus-adapter-projector-allowed: adapter + projector one loop
#   - gemma4-shared-backbone: freeze base, train projector + LoRA
#   - gemma4-always-vision: mmproj co-trains with the LoRA
#
# Concrete outline (fill in the peer's training-code choice — transformers +
# peft, unsloth, torchtune, or handcoded):
#
# from transformers import AutoModelForVision2Seq, AutoProcessor, BitsAndBytesConfig
# from peft import LoraConfig, get_peft_model
# from datasets import load_dataset
# import torch
#
# base = AutoModelForVision2Seq.from_pretrained(
#     "base/",
#     torch_dtype=torch.bfloat16,
#     quantization_config=BitsAndBytesConfig(
#         load_in_4bit=True,
#         bnb_4bit_compute_dtype=torch.bfloat16,
#         bnb_4bit_quant_type="nf4",
#         bnb_4bit_use_double_quant=True,
#     ),
# )
# lora = LoraConfig(
#     r=64, lora_alpha=128,
#     target_modules=["q_proj","k_proj","v_proj","o_proj","gate_proj","up_proj","down_proj"],
#     modules_to_save=["mm_projector","classifier"],
#     bias="none", task_type="CAUSAL_LM",
# )
# model = get_peft_model(base, lora)
# ds = load_dataset("dataset/", split="train")
# # rerank head: 4-way multiple-choice over candidate edits
# # loss: cross-entropy on rank-1 candidate + auxiliary regression on PF/SC/PQ scalars
# # optimizer: torch.optim.AdamW(fp32 state) on LoRA + projector + head only
# # gradient checkpointing on
# # save every 500 steps, keep best-eval
raise SystemExit("TODO(peer): implement training loop; see comments for shape")
PY

echo "[maskscore-image] upload to $OUT_REPO"
python3 -c "
from huggingface_hub import create_repo, upload_large_folder
create_repo('$OUT_REPO', repo_type='model', exist_ok=True)
"
hf upload-large-folder "$OUT_REPO" ./output --repo-type=model --num-workers=4

# Provenance
cat > /tmp/PROV.md <<EOF
# MaskScore-Image head — Gemma-4-12B QAT LoRA

- **Backbone:** $BASE
- **Dataset:** $DATASET
- **Training compute:** Vast.ai instance $VAST_INSTANCE_ID
- **Precision:** bf16 master + fp32 Adam + 4-bit nf4 forward (per qaft-precision-split)
- **Head shape:** rerank (4-way over candidate edits) + auxiliary PF/SC/PQ regression
- **Adapter+projector:** trained together per qat-4bit-plus-adapter-projector-allowed
- **Training date:** $(date -u +%FT%TZ)
EOF
hf upload "$OUT_REPO" /tmp/PROV.md FORK_PROVENANCE.md

echo "[maskscore-image] done — instance will self-destroy on exit"
