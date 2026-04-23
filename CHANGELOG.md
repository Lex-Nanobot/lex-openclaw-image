# Changelog

All notable changes to the Lex OpenClaw image are documented here.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.1.0] - 2026-04-23

### Added
- First Lex-flavored OpenClaw image release. Base: `ghcr.io/openclaw/openclaw:2026.4.22`.
- **Static binaries baked into `/usr/local/bin`**: gogcli v0.12.0, 1Password CLI v2.30.3, GitHub CLI v2.89.0, blogwatcher v0.0.2, yt-dlp 2025.01.26, ffmpeg (BtbN latest static build).
- **Node globals (system-wide)**: clawhub, @google/gemini-cli, @anthropic-ai/claude-code, @xdevplatform/xurl, agent-media-cli, @tobilu/qmd, @playwright/test.
- **Playwright Chromium** via `playwright install --with-deps chromium` — pulls in the Ubuntu packages headless Chromium needs.
- **memo wrapper** at `/usr/local/bin/memo` for Apple Notes CLI via Tailscale SSH into alex-mac-mini. The SSH key stays a runtime bind mount.
- **lex-telemetry hook** at `/home/node/.openclaw/hooks/lex-telemetry/` — copied in from the `hooks/lex-telemetry` git submodule. Picked up automatically by OpenClaw's hook directory scan at boot.
- **Globally-scoped skills** installed to `/.openclaw/skills/` via `clawhub install <slug> --workdir /.openclaw/skills/`: agent-browser-clawdbot, apify, blogwatcher, ffmpeg, market-research, playwright-cli-openclaw, self-improving-agent, seo-content-writer, topic-monitor, transcriptapi. (`marketing-strategy-pmm` and `memelord` deferred to v0.1.1 — see task #33.) Root-level install path (not `/home/node/.openclaw/` and not clawhub's default `/app/skills/`) matches Lex's "global skills" convention — genuinely user-agnostic and distinct from per-user OpenClaw config.

### Notes
- Runtime still needs these bind-mounts from `/lex/instances/<slug>/` or `/home/node/.openclaw/credentials/`:
  - `op-token` — 1Password service account token used for runtime agent-media key refresh
  - `gogcli/` config + encrypted keyring
  - `.xurl` config
  - `.ssh/lex_ed25519` for memo
- No database or migration changes on the image side. Downstream consumers (lex-platform) pin by immutable digest (`Instance.image_digest`), not tag; tag mutation after freeze cannot reskin existing instances.
