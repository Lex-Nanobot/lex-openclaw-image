# Changelog

All notable changes to the Lex OpenClaw image are documented here.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.1.1] - 2026-04-26

### Added
- **Firstboot secrets exchange** (`hooks/lex-firstboot-fetch.sh` +
  `hooks/lex-entrypoint.sh`, baked into `/usr/local/bin/`). Audit doc:
  `lex-drive/documents/secret-handling-audit-v1.md` (CRIT-2 fix).
  - Replaces the upstream `docker-entrypoint.sh` ENTRYPOINT with a thin
    wrapper that runs the firstboot fetch once, then `exec`s the
    upstream entrypoint with whatever CMD was inherited (typically
    `node ...`).
  - The fetch script POSTs the burn-once bootstrap-token from
    `/lex/secrets/bootstrap-token` to
    `${LEX_PLATFORM_URL}/api/provisioning/instances/${LEX_INSTANCE_ID}/firstboot/`,
    receives the shared MiniMax key (or empty env for BYO-only
    instances), writes `tenant.env`, and shreds the token.
  - **Required env vars at container start**: `LEX_INSTANCE_ID` and
    `LEX_PLATFORM_URL`. Both are set by `lex-droplet-agent` v0.1.3+
    via `-e` flags on `docker run`. Without either, the fetch
    fails-soft (logs to stderr, exits 0) and the container starts in
    BYO-only mode.
  - Fully idempotent on container restart: if `tenant.env` already has
    content, the fetch is skipped.

### Notes
- Pairs with `lex-droplet-agent` v0.1.3 (which adds the `-e
  LEX_INSTANCE_ID=...` and `-e LEX_PLATFORM_URL=...` flags) and
  `lex-platform`'s new `InstanceFirstBootView` at
  `/api/provisioning/instances/<uuid>/firstboot/`.
- No skill changes in this release. The `playwright-cli-openclaw` /
  `marketing-strategy-pmm` / `memelord` re-add (originally targeted at
  v0.1.1) is deferred to v0.1.2.

## [0.1.0] - 2026-04-23

### Added
- First Lex-flavored OpenClaw image release. Base: `ghcr.io/openclaw/openclaw:2026.4.22`.
- **Static binaries baked into `/usr/local/bin`**: gogcli v0.12.0, 1Password CLI v2.30.3, GitHub CLI v2.89.0, blogwatcher v0.0.2, yt-dlp 2025.01.26, ffmpeg (BtbN latest static build).
- **Node globals (system-wide)**: clawhub, @google/gemini-cli, @anthropic-ai/claude-code, @xdevplatform/xurl, agent-media-cli, @tobilu/qmd, @playwright/test.
- **Playwright Chromium** via `playwright install --with-deps chromium` — pulls in the Ubuntu packages headless Chromium needs.
- **memo wrapper** at `/usr/local/bin/memo` for Apple Notes CLI via Tailscale SSH into alex-mac-mini. The SSH key stays a runtime bind mount.
- **lex-telemetry hook** at `/home/node/.openclaw/hooks/lex-telemetry/` — copied in from the `hooks/lex-telemetry` git submodule. Picked up automatically by OpenClaw's hook directory scan at boot.
- **Globally-scoped skills** installed to `/.openclaw/skills/<bare-slug>/` via sparse-checkout from `github.com/openclaw/skills` (clawhub's canonical archive, mirrored via `clawdhub[bot]` on every publish) pinned at SHA `b6b31a72276f8abf29fedc2aeb7ce0aa890897aa`. Skills included: agent-browser-clawdbot, apify, blogwatcher, ffmpeg (upstream `openclaw/ffmpeg-skill`, normalized), market-research, self-improving-agent, seo-content-writer, topic-monitor, transcriptapi. Root-level install path (not `/home/node/.openclaw/` and not clawhub's default `/app/skills/`) matches Lex's "global skills" convention. Pulling from the git archive instead of `clawhub install` avoids clawhub's per-IP 180/15min rate limit (which caused CI builds to flake even when local builds succeeded). `playwright-cli-openclaw`, `marketing-strategy-pmm`, and `memelord` deferred to v0.1.1 — see task #33.

### Notes
- Runtime still needs these bind-mounts from `/lex/instances/<slug>/` or `/home/node/.openclaw/credentials/`:
  - `op-token` — 1Password service account token used for runtime agent-media key refresh
  - `gogcli/` config + encrypted keyring
  - `.xurl` config
  - `.ssh/lex_ed25519` for memo
- No database or migration changes on the image side. Downstream consumers (lex-platform) pin by immutable digest (`Instance.image_digest`), not tag; tag mutation after freeze cannot reskin existing instances.
