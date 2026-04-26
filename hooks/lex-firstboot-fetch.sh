#!/bin/bash
# lex-firstboot-fetch.sh -- container-side half of CRIT-2 (audit doc:
# lex-drive/documents/secret-handling-audit-v1.md).
#
# Runs once per container start, immediately before the upstream
# OpenClaw entrypoint takes over. Exchanges the burn-once
# bootstrap-token for the per-instance tenant secrets (shared MiniMax
# key, etc.), writes them into tenant.env, and shreds the
# bootstrap-token so a re-exec can't re-attempt.
#
# Idempotent: if tenant.env already has content (e.g. container restart
# after first successful boot), the script exits 0 without touching
# anything. Restart-as-unless-stopped is the usual hot path.
#
# Fail-soft: if any step fails (network error, 4xx/5xx from the
# platform, missing env var, missing token), we log to stderr and exit
# 0 so the upstream OpenClaw entrypoint still runs. The container then
# starts without provider keys and the customer can add their own via
# the post-provision UI. This matches the platform's empty-env
# response shape (apps/provisioning/views.py InstanceFirstBootView).
#
# Required env vars (set by lex-droplet-agent v0.1.3+ via -e flags on
# `docker run`; see lex-droplet-agent services/docker.py:build_run_args):
#
#   LEX_INSTANCE_ID    UUID of this instance
#   LEX_PLATFORM_URL   Platform base URL, e.g. https://api.lexnano.com
#
# Required mounted file:
#
#   /lex/secrets/bootstrap-token   plaintext burn-once token, mode 0600
#
# Outputs:
#
#   /lex/secrets/tenant.env        env-file consumed by the upstream
#                                  entrypoint (and also already mounted
#                                  via --env-file= on docker run)
#
# Wire contract:
#
#   POST <LEX_PLATFORM_URL>/api/provisioning/instances/<LEX_INSTANCE_ID>/firstboot/
#   Authorization: Bearer <bootstrap-token>
#
#   200 OK
#   {
#     "instance_id": "<uuid>",
#     "provider": "minimax" | "none",
#     "model_id": "MiniMax-M2" | "",
#     "env": {
#       "ANTHROPIC_API_KEY": "<shared-minimax-key>",
#       "ANTHROPIC_BASE_URL": "https://api.minimax.io/anthropic"
#     }
#   }
#
# (env may be {} when the platform has no shared key configured; the
# script writes an empty tenant.env in that case so the idempotency
# guard still trips on the next restart.)
set -uo pipefail

SECRETS_DIR="${LEX_SECRETS_DIR:-/lex/secrets}"
TOKEN_FILE="${SECRETS_DIR}/bootstrap-token"
ENV_FILE="${SECRETS_DIR}/tenant.env"

log() {
    # Prefix every line so it's grep-able in container logs.
    printf '[lex-firstboot] %s\n' "$*" >&2
}

# 1. Idempotency guard. If tenant.env already has content, we've
#    already exchanged once. Skip silently.
if [ -s "${ENV_FILE}" ]; then
    log "tenant.env already populated, skipping firstboot exchange"
    exit 0
fi

# 2. Required env vars. Missing either is a misconfigured deploy
#    (lex-droplet-agent v0.1.3+ sets both via -e flags on docker run).
#    Fail-soft so the container still starts.
if [ -z "${LEX_INSTANCE_ID:-}" ]; then
    log "LEX_INSTANCE_ID not set; skipping firstboot exchange"
    exit 0
fi
if [ -z "${LEX_PLATFORM_URL:-}" ]; then
    log "LEX_PLATFORM_URL not set; skipping firstboot exchange"
    exit 0
fi

# 3. Bootstrap token. Mounted by lex-droplet-agent into
#    /lex/instances/<slug>/secrets/bootstrap-token; the container sees
#    it at /lex/secrets/bootstrap-token because the instance secrets
#    dir is volume-mounted at /lex/secrets.
if [ ! -s "${TOKEN_FILE}" ]; then
    log "no bootstrap-token at ${TOKEN_FILE}; skipping firstboot exchange"
    exit 0
fi
TOKEN=$(cat "${TOKEN_FILE}")

# 4. POST to the firstboot endpoint. -fS makes curl exit non-zero on
#    HTTP >=400 while still emitting the response body (which carries
#    the typed error from DRF).
URL="${LEX_PLATFORM_URL%/}/api/provisioning/instances/${LEX_INSTANCE_ID}/firstboot/"
log "fetching tenant secrets from ${URL}"

RESPONSE=$(curl -fsS -X POST \
    -H "Authorization: Bearer ${TOKEN}" \
    -H "Accept: application/json" \
    --max-time 30 \
    "${URL}" 2>&1) || {
    log "firstboot exchange failed: ${RESPONSE}"
    log "container starting without provider keys (BYO-only mode)"
    exit 0
}

# 5. Parse response.env and emit env-file lines. jq is in the upstream
#    openclaw image already; if it's missing for some reason, fall back
#    to a python one-liner so we still ship something.
TMP_ENV="${ENV_FILE}.tmp.$$"
trap "rm -f ${TMP_ENV}" EXIT

if command -v jq >/dev/null 2>&1; then
    if ! echo "${RESPONSE}" | jq -er '.env | to_entries[] | "\(.key)=\(.value)"' \
        > "${TMP_ENV}" 2>/dev/null; then
        # `jq -er` on an empty .env returns a non-empty exit. Confirm
        # by parsing whether .env is just an empty object.
        if echo "${RESPONSE}" | jq -e '.env | length == 0' >/dev/null 2>&1; then
            log "platform returned empty env (no shared provider key); writing empty tenant.env"
            : > "${TMP_ENV}"
        else
            log "could not parse .env from response; container starting without provider keys"
            exit 0
        fi
    fi
elif command -v python3 >/dev/null 2>&1; then
    if ! echo "${RESPONSE}" | python3 -c '
import json, sys
data = json.load(sys.stdin)
for k, v in (data.get("env") or {}).items():
    print(f"{k}={v}")
' > "${TMP_ENV}" 2>/dev/null; then
        log "could not parse .env from response (python fallback); container starting without provider keys"
        exit 0
    fi
else
    log "neither jq nor python3 available; cannot parse firstboot response"
    exit 0
fi

# 6. Atomic install. chmod first, then mv, so the file is never
#    readable by other users between creation and final permissions.
chmod 0600 "${TMP_ENV}"
mv "${TMP_ENV}" "${ENV_FILE}"
trap - EXIT

PROVIDER=$(echo "${RESPONSE}" | (jq -r '.provider // "unknown"' 2>/dev/null || echo "unknown"))
log "firstboot exchange complete (provider=${PROVIDER}); tenant.env populated"

# 7. Burn the bootstrap-token locally so a re-exec of this script
#    cannot re-attempt the exchange. The platform-side token has
#    already been burned by BootstrapTokenAuthentication.consume so
#    this is defense in depth, not the primary control.
shred -u "${TOKEN_FILE}" 2>/dev/null || rm -f "${TOKEN_FILE}"

exit 0
