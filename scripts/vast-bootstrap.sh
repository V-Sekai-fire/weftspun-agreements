#!/usr/bin/env bash
# Vast.ai instance bootstrap — one-shot, idempotent, self-destroying.
# Runs after `vastai launch`. Prereqs (embedded in Vast userdata):
#   VAST_INSTANCE_ID     numeric id of this instance (Vast provides)
#   VAULT_APPROLE_ID     Bao AppRole role_id for `vast-instance`
#   VAULT_APPROLE_SECRET Bao AppRole secret_id (short-lived, one-shot)
#   TS_AUTHKEY           Tailscale ephemeral auth key (pre-authorized)
# Everything else derives from Bao once the AppRole login succeeds.

set -euo pipefail

: "${VAST_INSTANCE_ID:?VAST_INSTANCE_ID must be set in Vast userdata}"
: "${VAULT_APPROLE_ID:?VAULT_APPROLE_ID must be set in Vast userdata}"
: "${VAULT_APPROLE_SECRET:?VAULT_APPROLE_SECRET must be set in Vast userdata}"
: "${TS_AUTHKEY:?TS_AUTHKEY must be set in Vast userdata}"

BAO_ADDR="https://weftspun-bao.stonecat-ratio.ts.net:8200"
export BAO_ADDR

# Destroy-on-exit trap — runs whether the workload succeeds or crashes.
# Reads its own kill-switch from a Bao-fetched vast api key so no
# credential lives in the exit path itself.
cleanup() {
    echo "[bootstrap] cleanup trap fired at $(date -u +%FT%TZ)" >&2
    if [ -n "${VAST_API_KEY:-}" ]; then
        curl -s -X DELETE \
            "https://console.vast.ai/api/v0/instances/${VAST_INSTANCE_ID}/?api_key=${VAST_API_KEY}" \
            >&2 || true
    fi
}
trap cleanup EXIT

# --- 1. Core deps ---
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
apt-get install -y -qq git curl wget jq python3 python3-pip build-essential \
    ca-certificates gnupg lsb-release

# --- 2. Tailscale (reach the tailnet-only Bao endpoint) ---
curl -fsSL https://tailscale.com/install.sh | sh
tailscale up --auth-key="$TS_AUTHKEY" --hostname="vast-${VAST_INSTANCE_ID}" \
    --ssh --accept-routes
# Wait for the tailnet DNS to resolve the Bao host
for i in $(seq 1 30); do
    if getent hosts weftspun-bao.stonecat-ratio.ts.net >/dev/null; then break; fi
    sleep 2
done

# --- 3. Bao CLI + AppRole login → short-lived client cert ---
curl -fsSL https://apt.releases.hashicorp.com/gpg | gpg --dearmor -o /usr/share/keyrings/hashicorp.gpg
echo "deb [signed-by=/usr/share/keyrings/hashicorp.gpg] https://apt.releases.hashicorp.com $(lsb_release -cs) main" \
    > /etc/apt/sources.list.d/hashicorp.list
apt-get update -qq
apt-get install -y -qq openbao || apt-get install -y -qq vault

# Bootstrap trust anchor: fetch the workspace CA over TLS (the Bao endpoint
# presents its own chain, but we need to trust it for the mTLS login).
mkdir -p /root/.bao-creds
curl -fsSL "$BAO_ADDR/v1/pki/ca_chain" -o /root/.bao-creds/ca-chain.pem
export BAO_CACERT=/root/.bao-creds/ca-chain.pem

# AppRole login → short-lived token
export BAO_TOKEN=$(bao write -field=token auth/approle/login \
    role_id="$VAULT_APPROLE_ID" secret_id="$VAULT_APPROLE_SECRET")

# Issue an instance-scoped client cert (24h TTL, CN pinned to this instance)
CN="vast-${VAST_INSTANCE_ID}.instances.weftspun"
bao write -format=json pki/issue/vast-instance \
    common_name="$CN" ttl=24h \
    > /tmp/instance-cert.json
python3 -c "
import json
d = json.load(open('/tmp/instance-cert.json'))['data']
open('/root/.bao-creds/instance-cert.pem','w').write(d['certificate'] + '\n' + d['issuing_ca'])
open('/root/.bao-creds/instance-key.pem','w').write(d['private_key'])
"
chmod 600 /root/.bao-creds/instance-key.pem
rm /tmp/instance-cert.json

# Swap to the mTLS identity for the rest of the session
export BAO_CLIENT_CERT=/root/.bao-creds/instance-cert.pem
export BAO_CLIENT_KEY=/root/.bao-creds/instance-key.pem
unset BAO_TOKEN
# Re-login via cert to get a token scoped to vast-instance-agent policy
export BAO_TOKEN=$(bao login -method=cert -no-store -token-only)

# --- 4. Fetch Vast API key (for the self-destroy trap) + Tigris + HF ---
export VAST_API_KEY=$(bao kv get -field=value secret/vast/api_key)
export HF_TOKEN=$(bao kv get -field=value secret/hf/write-token)
eval $(bao kv get -format=json secret/tigris/sccache | python3 -c "
import json, sys
d = json.load(sys.stdin)['data']['data']
for k in ('AWS_ACCESS_KEY_ID','AWS_SECRET_ACCESS_KEY','AWS_ENDPOINT_URL_S3','AWS_REGION','SCCACHE_BUCKET'):
    print(f'export {k}={d[k]}')
")

# --- 5. Claude Code ---
curl -fsSL https://claude.ai/install.sh | bash
export PATH="$HOME/.local/bin:$PATH"
CLAUDE_TOKEN=$(bao kv get -field=value secret/claude-code/vast-fleet-token)
echo "$CLAUDE_TOKEN" | claude auth login --token || true
unset CLAUDE_TOKEN

# --- 6. Google repo + manifest sync ---
mkdir -p /root/.local/bin
curl -fsSL https://storage.googleapis.com/git-repo-downloads/repo -o /root/.local/bin/repo
chmod +x /root/.local/bin/repo
export PATH="/root/.local/bin:$PATH"

mkdir -p /workspace && cd /workspace
git config --global user.email "vast-${VAST_INSTANCE_ID}@instances.weftspun"
git config --global user.name "vast-${VAST_INSTANCE_ID}"
repo init -u https://github.com/v-sekai-fabric/weftspun-keypoint -b main
repo sync -j$(nproc)

# --- 7. Register in the fleet ---
bao kv put "agents/data/vast-${VAST_INSTANCE_ID}" \
    kind=vast \
    instance_id="$VAST_INSTANCE_ID" \
    cn="$CN" \
    started_at="$(date -u +%FT%TZ)" \
    gpu="${GPU_NAME:-unknown}" \
    workload="${WORKLOAD:-unknown}" \
    owner="vast-${VAST_INSTANCE_ID}"

# --- 8. Install HF CLI + hf-transfer + Mitsuba for the training/render scripts ---
pip install -q --upgrade huggingface_hub hf_transfer transformers peft \
    accelerate datasets bitsandbytes torch \
    mitsuba drjit  # for run-mitsuba-hammersley-corpus.sh (task #147)
export HF_HUB_ENABLE_HF_TRANSFER=1

# --- 9. Hand off to the per-workload training script ---
# Caller sets $TRAINING_SCRIPT in userdata; e.g. train-maskscore-image.sh
if [ -n "${TRAINING_SCRIPT:-}" ]; then
    bash "/workspace/2-contract/weftspun-agreements/scripts/${TRAINING_SCRIPT}"
else
    echo "[bootstrap] no TRAINING_SCRIPT set; idle for interactive session" >&2
    # Keep the trap live; sleep on a Bao-KV heartbeat so the instance stays
    # billable only while there's real work
    while true; do
        bao kv put "agents/data/vast-${VAST_INSTANCE_ID}" \
            heartbeat="$(date -u +%FT%TZ)" >/dev/null 2>&1 || true
        sleep 60
    done
fi
