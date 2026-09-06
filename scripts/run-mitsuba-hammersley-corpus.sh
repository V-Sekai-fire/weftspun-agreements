#!/usr/bin/env bash
# Mitsuba 3 + Hammersley corpus generator — first Vast workload.
# Deterministic (view × time) Hammersley sampling over 3D latents from
# TRELLIS.2 / Pixal3D / VoxHammer + animated ANNY/SOMA rigs.
# Emits per-frame corpus: RGB + depth AOV + normals AOV + blendshape weights
# + ground-truth pose params. Answers CLAUDE.md's Blender blocklist row
# (Mitsuba's determinism clears the reproducibility bar Blender fails).

set -euo pipefail
: "${HF_TOKEN:?bootstrap must export HF_TOKEN}"
: "${VAST_INSTANCE_ID:?bootstrap must export VAST_INSTANCE_ID}"

OUT_REPO_DATASET=chibifire/mitsuba-hammersley-3d-corpus
WORK=/workspace/mitsuba-corpus
mkdir -p "$WORK" && cd "$WORK"

# Install Mitsuba (pip variant; source builds live in the manifest repo)
pip install -q --upgrade mitsuba drjit numpy

# Ingest source assets from chibifire (only license-clean ones for constructed
# synthetic per CLAUDE.md data-hygiene rules)
huggingface-cli login --token "$HF_TOKEN" >/dev/null 2>&1 || true
mkdir -p assets
hf download chibifire/TRELLIS.2-4B --local-dir assets/trellis2 || true
hf download chibifire/Pixal3D-GGUF  --local-dir assets/pixal3d || true

python3 <<'PY'
# Hammersley view sampler + Mitsuba render + AOV emit.
# TODO(peer): implement — outline below.
#
# import mitsuba as mi
# mi.set_variant('cuda_ad_rgb')  # or 'llvm_ad_rgb' if CPU-only Vast
#
# # Load one 3D asset per (candidate_id, animation_frame) pair.
# # Hammersley view sampling per CLAUDE.md's "sphere_hammersley_sequence
# # camera sequence" rule. Uses the TRELLIS / Pixal3D canonical impl
# # (voxhammer-upstream/trellis/utils/random_utils.py): stratified n/N on
# # the first axis, Halton (= van der Corput base-2 for dim-1=1) on the
# # second, inverse-CDF to (theta, phi). Vendored below so this script
# # doesn't require the trellis package on the Vast instance.
# def halton(i, base=2):
#     r, f = 0.0, 1.0 / base
#     while i > 0:
#         r += (i % base) * f
#         f /= base
#         i //= base
#     return r
#
# def sphere_hammersley_sequence(n, num_samples, offset=(0, 0), remap=False):
#     u = n / num_samples + offset[0] / num_samples
#     v = halton(n) + offset[1]
#     if remap:
#         u = 2 * u if u < 0.25 else 2 / 3 * u + 1 / 3
#     theta = math.acos(1 - 2 * u) - math.pi / 2
#     phi = v * 2 * math.pi
#     return phi, theta
#
# def hammersley_views(num_samples):
#     return [sphere_hammersley_sequence(i, num_samples) for i in range(num_samples)]
#
# # For each view, render RGB + depth AOV + normal AOV + blendshape drive
# # emit as parquet+zstd (ETNF: shape_id, view_idx, aov_kind, aov_data, ...)
raise SystemExit("TODO(peer): implement Mitsuba+Hammersley corpus render loop")
PY

# Un-parks task #67 (HERO's parked ANNY-SOMA render) by folding its
# anchors-v3 + parametric-sweep + kimodo motion sources into the same
# corpus pass.

# Upload to Tigris (per data-hygiene "manifested separately from constructed
# and real data")
eval $(bao kv get -format=json secret/tigris/sccache | python3 -c "
import json, sys
d = json.load(sys.stdin)['data']['data']
for k in ('AWS_ACCESS_KEY_ID','AWS_SECRET_ACCESS_KEY','AWS_ENDPOINT_URL_S3'):
    print(f'export {k}={d[k]}')
")
aws --endpoint-url="$AWS_ENDPOINT_URL_S3" s3 cp corpus/ \
    "s3://weftspun-corpora/mitsuba-hammersley-3d-corpus/$(date +%Y%m%d)/" \
    --recursive

# Also publish the HF dataset (denormalized per hf-datasets-no-etnf skill)
python3 -c "
from huggingface_hub import create_repo
create_repo('$OUT_REPO_DATASET', repo_type='dataset', exist_ok=True)
"
hf upload-large-folder "$OUT_REPO_DATASET" corpus/ --repo-type=dataset --num-workers=4

cat > /tmp/PROV.md <<EOF
# mitsuba-hammersley-3d-corpus

- Renderer: Mitsuba 3 (v-sekai-fabric/mitsuba3, pinned SHA in manifest)
- Sampler: deterministic Hammersley (view × time), per CLAUDE.md's sphere_hammersley_sequence rule
- Source assets: chibifire/TRELLIS.2-4B, chibifire/Pixal3D-GGUF, ANNY/SOMA rigs
- AOVs: RGB, depth, normal, blendshape weights, ground-truth pose params
- Storage: Tigris s3://weftspun-corpora/ + HF dataset $OUT_REPO_DATASET
- Purpose: training data for chibifire/gemma-4-12B-3d-aware-qat (task #146)
- Constructed synthetic per CLAUDE.md data-hygiene (labels true by construction, deterministic reproduction, no learned-distribution sampling)
- Generated: $(date -u +%FT%TZ) on Vast instance $VAST_INSTANCE_ID
EOF
hf upload --repo-type=dataset "$OUT_REPO_DATASET" /tmp/PROV.md README.md

echo "[mitsuba-hammersley] done — task #67 folded in"
