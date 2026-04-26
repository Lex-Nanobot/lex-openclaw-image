#!/bin/bash
# lex-entrypoint.sh -- thin wrapper around upstream openclaw's
# `docker-entrypoint.sh`.
#
# We override ENTRYPOINT in our Lex layer's Dockerfile so the firstboot
# secrets exchange (lex-firstboot-fetch.sh) runs ONCE before OpenClaw
# proper starts. After the fetch returns (success or fail-soft), we
# `exec` the upstream entrypoint with whatever CMD was inherited from
# the upstream image (typically `node ...`).
#
# Why a wrapper instead of running the fetch from a CMD entrypoint:
#
#   * Docker only allows ONE ENTRYPOINT. To preserve upstream's
#     `docker-entrypoint.sh` behavior (signal forwarding, init
#     handling, env var massaging) we have to call it explicitly here
#     rather than skip it.
#
#   * The firstboot fetch must complete BEFORE OpenClaw boots,
#     because OpenClaw reads tenant.env at startup (and we can't reload
#     env into a running OpenClaw process).
#
# Fail-soft contract: lex-firstboot-fetch.sh always exits 0, even on
# error. This script does not gate OpenClaw startup on the fetch
# result. The container will start without provider keys if the fetch
# fails; the customer-facing UI surfaces the missing-key state.
set -e

/usr/local/bin/lex-firstboot-fetch.sh || true

# Upstream openclaw image declares Entrypoint as ["docker-entrypoint.sh"]
# (basename, relies on $PATH). We mirror that resolution here so a
# future upstream move of the script (e.g. /opt/openclaw/bin/) keeps
# working as long as it stays on PATH. If you ever need to debug a
# missing entrypoint, run `which docker-entrypoint.sh` inside the
# container to confirm the lookup path.
exec docker-entrypoint.sh "$@"
