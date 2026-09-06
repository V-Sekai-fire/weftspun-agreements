# Bao PKI role + policy shapes for Vast instances.
# NOT deployed by this file — operator applies via `bao write` + `bao policy write`.
# Documented here so the shape lives in git alongside the bootstrap script.

# --- PKI role: short-lived instance certs ---
# bao write pki/roles/vast-instance @vast-instance-role.json
#
# vast-instance-role.json:
# {
#   "allowed_domains":  "instances.weftspun",
#   "allow_subdomains": true,
#   "allow_bare_domains": false,
#   "allow_glob_domains": false,
#   "enforce_hostnames": true,
#   "server_flag": false,
#   "client_flag": true,
#   "key_type": "ec",
#   "key_bits": 256,
#   "max_ttl":  "24h",
#   "ttl":      "24h"
# }

# --- Bind cert-auth to policy ---
# bao write auth/cert/certs/vast-instance \
#   display_name=vast-instance \
#   allowed_common_names="*.instances.weftspun" \
#   policies=vast-instance-agent \
#   token_ttl=24h token_max_ttl=24h

# --- AppRole for bootstrap (issues the instance cert) ---
# bao write auth/approle/role/vast-bootstrap \
#   token_policies=vast-bootstrap \
#   token_ttl=15m token_max_ttl=15m \
#   secret_id_ttl=15m secret_id_num_uses=1 bind_secret_id=true
#
# (secret_id is generated per-instance-launch, embedded in Vast userdata,
#  one-shot, expires in 15 min — window for the bootstrap script to finish.)

# --- Policy: what a vast-bootstrap AppRole token can do ---
path "pki/issue/vast-instance" {
  capabilities = ["create","update"]
}
path "sys/mounts/pki" {
  capabilities = ["read"]
}

# --- Policy: what a vast-instance mTLS-authed token can do ---
# (attach as `vast-instance-agent`)
path "secret/data/tigris/sccache" {
  capabilities = ["read"]
}
path "secret/data/hf/write-token" {
  capabilities = ["read"]
}
path "secret/data/claude-code/vast-fleet-token" {
  capabilities = ["read"]
}
path "secret/data/vast/api_key" {
  capabilities = ["read"]
}
# Own row under agents/ for fleet visibility + heartbeat
path "agents/data/{{identity.entity.aliases.auth_cert_443e3aa2.name}}" {
  capabilities = ["create","read","update","delete"]
}
# Own credential subtree per agents-own-rw pattern (memory rebac-herd-writes-peers-read)
path "secret/data/agents-own/{{identity.entity.aliases.auth_cert_443e3aa2.name}}/*" {
  capabilities = ["create","read","update","delete"]
}
path "secret/metadata/agents-own/{{identity.entity.aliases.auth_cert_443e3aa2.name}}/*" {
  capabilities = ["read","delete","list"]
}
