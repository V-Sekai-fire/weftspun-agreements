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

All 9 MaskScore modality heads (per the amended
`maskscore-is-editscore-analog` memory 2026-09-06):

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

| workload                | GPU              | ~cost/hr   | ~duration | ~run cost |
|-------------------------|------------------|------------|-----------|-----------|
| MaskScore-Image         | RTX A6000 48 GB  | $0.50-0.80 | 2-6h      | $3-15     |
| MaskScore-Text          | RTX A6000 48 GB  | $0.50-0.80 | 1-3h      | $2-8      |
| MaskScore-Motion        | RTX A6000 48 GB  | $0.50-0.80 | 2-6h      | $3-15     |
| MaskScore-Audio         | RTX A6000 48 GB  | $0.50-0.80 | 3-8h      | $4-20     |
| MaskScore-Mesh          | RTX A6000 48 GB  | $0.50-0.80 | 3-6h      | $3-15     |
| MaskScore-Pose          | RTX A6000 48 GB  | $0.50-0.80 | 1-3h      | $2-8      |
| MaskScore-Depth         | RTX A6000 48 GB  | $0.50-0.80 | 2-4h      | $2-10     |
| MaskScore-Blendshape    | RTX A6000 48 GB  | $0.50-0.80 | 2-4h      | $2-10     |
| MaskScore-Video         | RTX A6000 48 GB  | $0.50-0.80 | 4-10h     | $5-25     |

All fit A6000 48 GB — same 40 GB Gemma-4-12B QAT working set + per-modality
LoRA + projector adds only ~200-500 MB. **Full-fleet sweep: $30-140.**
Current Vast account balance ~$45.62 (2026-09-06) covers roughly the first
3-4 modalities; full 9-head sweep needs an operator top-up to ~$150 for
comfortable headroom.

## Related memories

- `4bit-qaft-is-default` — QAT-4bit is the default shipping quant
- `qaft-precision-split` — bf16 master + fp32 Adam + 4-bit forward
- `qat-4bit-plus-adapter-projector-allowed` — adapter + projector one loop
- `gemma4-shared-backbone` — one backbone, many heads
- `maskscore-is-editscore-analog` — the doctrine this scripts implement
- `rebac-herd-writes-peers-read` — Bao secret-flow shape this bootstrap follows
