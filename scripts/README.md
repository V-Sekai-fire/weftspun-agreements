# Vast.ai rental scripts

Instance-side bootstrap + MaskScore training skeletons for Vast.ai
QAFT runs. Landed 2026-09-06 alongside the Vast un-blocklist row
(see `../BLOCKLIST.md` "Vast.ai is blocklisted as rented compute").

## Files

- `vast-bootstrap.sh` — one-shot, idempotent, self-destroying instance
  bootstrap. Runs after `vastai launch`, sets up Tailscale + Bao mTLS
  identity + Claude Code + Google `repo` sync, registers in the fleet
  at `agents/data/vast-<id>`, then hands off to a per-workload training
  script. `trap cleanup EXIT` calls `vastai destroy` no matter how the
  workload exits.

**Upstream sequence** (runs BEFORE any MaskScore head):

- `run-mitsuba-hammersley-corpus.sh` — task #147, first Vast workload.
  Deterministic Hammersley view sampling + Mitsuba 3 renders emitting
  RGB/depth/normals AOVs + blendshape/pose ground truth. Folds in
  task #67 (parked ANNY-SOMA render). Publishes to Tigris +
  `chibifire/mitsuba-hammersley-3d-corpus` HF dataset. Mitsuba is the
  sanctioned constructed-synthetic renderer (answers the Blender
  blocklist row's reproducibility concern).

- `train-gemma4-3d-vision-ft.sh` — task #146, second Vast workload.
  Consumes the Mitsuba corpus; QAFT fine-tunes Gemma-4-12B's vision
  head + adapter on cross-view consistency + view synthesis + latent
  reconstruction. Emits `chibifire/gemma-4-12B-3d-aware-qat`, which
  supersedes vanilla `chibifire/gemma-4-12B-it-qat-q4_0-unquantized`
  as the MaskScore backbone.

**Then** all 9 MaskScore modality heads (per the amended
`maskscore-is-editscore-analog` memory 2026-09-06). Each script's
BASE_3D variable is commented in for use once task #146 lands; until
then, all 9 fall back to the vanilla Gemma-4-12B QAT base with a note:

- `train-maskscore-image.sh` — LoRA on EditReward-Bench. **Runnable.**
- `train-maskscore-text.sh` — code-diff / instruction rerank. BLOCKED on `TODO(dataset)`.
- `train-maskscore-motion.sh` — motion-diffusion rerank. BLOCKED on `TODO(motion-kl)`.
- `train-maskscore-audio.sh` — voice-clone rerank. BLOCKED on `TODO(voice-bolt)`.
- `train-maskscore-mesh.sh` — 3D-mesh rerank (TRELLIS.2 / Pixal3D / VoxHammer). BLOCKED on `TODO(mesh-metric)`.
- `train-maskscore-pose.sh` — pose-fit rerank. BLOCKED on `TODO(dataset)`.
- `train-maskscore-depth.sh` — depth-map rerank. BLOCKED on `TODO(dataset)` + See-Through license.
- `train-maskscore-blendshape.sh` — facial-blendshape (52 FACS action-units) rerank. BLOCKED on `TODO(dataset)`.
- `train-maskscore-video.sh` — video rerank (wan-vace / --write-movie). BLOCKED on `TODO(dataset)`.

- `vast-bao-policies.hcl` — Bao PKI role, cert-auth binding, AppRole,
  and policy shapes for the Vast instance identity. **Not deployed
  by this file** — operator applies via `bao write` + `bao policy write`.

## Vast userdata contract

`vastai launch` must set these env vars in the instance's userdata:

```
VAST_INSTANCE_ID     # numeric id (Vast provides in userdata by default)
VAULT_APPROLE_ID     # bao auth/approle/role/vast-bootstrap role_id
VAULT_APPROLE_SECRET # bao auth/approle/role/vast-bootstrap/secret-id (one-shot, 15 min TTL)
TS_AUTHKEY           # Tailscale ephemeral pre-authorized auth key
TRAINING_SCRIPT      # e.g. train-maskscore-image.sh (or leave unset for idle session)
GPU_NAME             # cosmetic, for the fleet registration row
WORKLOAD             # cosmetic, for the fleet registration row
```

## Cost expectations (2026-09-06 baseline)

| workload                                | GPU                   | ~cost/hr   | ~duration | ~run cost |
|-----------------------------------------|-----------------------|------------|-----------|-----------|
| **#147 Mitsuba+Hammersley corpus**      | CPU-heavy (any 16c+)  | $0.10-0.30 | 6-24h     | $2-8      |
| **#146 Gemma-4-12B 3D-shape FT**        | RTX A6000 48 GB       | $0.50-0.80 | 6-12h     | $5-15     |
| MaskScore-Image                         | RTX A6000 48 GB       | $0.50-0.80 | 2-6h      | $3-15     |
| MaskScore-Text          | RTX A6000 48 GB  | $0.50-0.80 | 1-3h      | $2-8      |
| MaskScore-Motion        | RTX A6000 48 GB  | $0.50-0.80 | 2-6h      | $3-15     |
| MaskScore-Audio         | RTX A6000 48 GB  | $0.50-0.80 | 3-8h      | $4-20     |
| MaskScore-Mesh          | RTX A6000 48 GB  | $0.50-0.80 | 3-6h      | $3-15     |
| MaskScore-Pose          | RTX A6000 48 GB  | $0.50-0.80 | 1-3h      | $2-8      |
| MaskScore-Depth         | RTX A6000 48 GB  | $0.50-0.80 | 2-4h      | $2-10     |
| MaskScore-Blendshape    | RTX A6000 48 GB  | $0.50-0.80 | 2-4h      | $2-10     |
| MaskScore-Video         | RTX A6000 48 GB  | $0.50-0.80 | 4-10h     | $5-25     |

Corpus (#147) runs on CPU-only Vast offers (cheaper). 3D-shape FT (#146)
and all 9 MaskScore heads fit A6000 48 GB — same 40 GB Gemma-4-12B QAT
working set + per-modality LoRA + projector adds only ~200-500 MB.
**Full sequence sweep (#147 → #146 → 9 MaskScore heads): $37-163.**
Current Vast account balance ~$45.62 (2026-09-06) covers #147 + #146 +
first 2-3 MaskScore heads; full pipeline needs an operator top-up to
~$200 for comfortable headroom.

## Related memories

- `4bit-qaft-is-default` — QAT-4bit is the default shipping quant
- `qaft-precision-split` — bf16 master + fp32 Adam + 4-bit forward
- `qat-4bit-plus-adapter-projector-allowed` — adapter + projector one loop
- `gemma4-shared-backbone` — one backbone, many heads
- `maskscore-is-editscore-analog` — the doctrine this scripts implement
- `rebac-herd-writes-peers-read` — Bao secret-flow shape this bootstrap follows
