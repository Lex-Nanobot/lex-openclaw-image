# syntax=docker/dockerfile:1.7
#
# Lex-flavored OpenClaw image.
#
# Pinned to openclaw:2026.4.22 as of v0.1.0. Upgrades happen by bumping
# UPSTREAM_TAG AND the VERSION file, not by tracking :latest — smoke-test
# upstream changes on a throwaway tag first, then promote.
#
# Layer order is deliberate: most-stable on top, most-changeable on bottom,
# so bumping the skill list does not invalidate the ~250MB Chromium layer.

ARG UPSTREAM_TAG=2026.4.22
FROM ghcr.io/openclaw/openclaw:${UPSTREAM_TAG}

# -----------------------------------------------------------------------------
# Layer 1: system apt deps for the binary installers below.
# -----------------------------------------------------------------------------
USER root

RUN apt-get update \
 && apt-get install -y --no-install-recommends \
      ca-certificates \
      curl \
      git \
      tar \
      unzip \
      xz-utils \
 && rm -rf /var/lib/apt/lists/*

# -----------------------------------------------------------------------------
# Layer 2: static binaries → /usr/local/bin (version-pinned).
#
# Pins come from lex-platform reinstall.sh. To bump, update the URL +
# tarball member here and cut a new image tag; never float these.
# -----------------------------------------------------------------------------

# gogcli (Google Drive + Gmail CLI)
RUN curl -fsSL "https://github.com/steipete/gogcli/releases/download/v0.12.0/gogcli_0.12.0_linux_amd64.tar.gz" \
      | tar -xzO gog > /usr/local/bin/gog \
 && chmod +x /usr/local/bin/gog

# 1Password CLI (op)
RUN curl -fsSL "https://cache.agilebits.com/dist/1P/op2/pkg/v2.30.3/op_linux_amd64_v2.30.3.zip" \
      -o /tmp/op.zip \
 && unzip -o /tmp/op.zip -d /tmp/op_extracted \
 && cp /tmp/op_extracted/op /usr/local/bin/op \
 && chmod +x /usr/local/bin/op \
 && rm -rf /tmp/op.zip /tmp/op_extracted

# GitHub CLI (gh)
RUN curl -fsSL "https://github.com/cli/cli/releases/download/v2.89.0/gh_2.89.0_linux_amd64.tar.gz" \
      | tar -xzO gh_2.89.0_linux_amd64/bin/gh > /usr/local/bin/gh \
 && chmod +x /usr/local/bin/gh

# blogwatcher
RUN curl -fsSL "https://github.com/Hyaxia/blogwatcher/releases/download/v0.0.2/blogwatcher_0.0.2_linux_amd64.tar.gz" \
      | tar -xzO blogwatcher > /usr/local/bin/blogwatcher \
 && chmod +x /usr/local/bin/blogwatcher

# yt-dlp
RUN curl -fsSL "https://github.com/yt-dlp/yt-dlp/releases/download/2025.01.26/yt-dlp" \
      -o /usr/local/bin/yt-dlp \
 && chmod +x /usr/local/bin/yt-dlp

# ffmpeg (BtbN static build)
RUN curl -fsSL "https://github.com/BtbN/FFmpeg-Builds/releases/download/latest/ffmpeg-master-latest-linux64-gpl.tar.xz" \
      -o /tmp/ffmpeg.tar.xz \
 && cd /tmp \
 && xz -d ffmpeg.tar.xz \
 && tar -xf ffmpeg.tar \
 && cp /tmp/ffmpeg-master-latest-linux64-gpl/bin/ffmpeg /usr/local/bin/ffmpeg \
 && chmod +x /usr/local/bin/ffmpeg \
 && rm -rf /tmp/ffmpeg.tar /tmp/ffmpeg-master-latest-linux64-gpl

# -----------------------------------------------------------------------------
# Layer 3: npm globals (system-wide, not per-user-home).
#
# `-g` with no --prefix installs into /usr/local so every user on the
# image — including runtime-invoked shells — can find them on PATH.
# -----------------------------------------------------------------------------

RUN npm install -g --omit=dev --no-audit --no-fund \
      clawhub \
      @google/gemini-cli \
      @anthropic-ai/claude-code \
      @xdevplatform/xurl \
      agent-media-cli \
      @tobilu/qmd \
      @playwright/test

# -----------------------------------------------------------------------------
# Layer 4: Playwright Chromium + its apt deps.
#
# --with-deps pulls in the Ubuntu packages headless Chromium needs
# (libnss3, libatk1.0-0, libcups2, etc.). This is the biggest single
# layer (~250MB) so it stays in its own RUN for cache reuse.
# -----------------------------------------------------------------------------

RUN playwright install --with-deps chromium

# -----------------------------------------------------------------------------
# Layer 5: the memo wrapper.
#
# Wraps Tailscale SSH into alex-mac-mini for Apple Notes CLI access.
# The SSH key at /home/node/.openclaw/.ssh/lex_ed25519 stays a runtime
# bind mount — it is NEVER baked into the image.
# -----------------------------------------------------------------------------

COPY scripts/memo /usr/local/bin/memo
RUN chmod +x /usr/local/bin/memo

# -----------------------------------------------------------------------------
# Layer 6: lex-telemetry hook.
#
# COPY from the image repo's hooks/ submodule into the OpenClaw hooks
# tree. OpenClaw discovers hooks by directory scan on boot — no manifest
# registration step needed. Ownership goes to node:node so the gateway
# user can read + execute it.
# -----------------------------------------------------------------------------

COPY --chown=node:node hooks/lex-telemetry /home/node/.openclaw/hooks/lex-telemetry

# -----------------------------------------------------------------------------
# Layer 7: globally-installed skills from the openclaw/skills archive.
#
# clawhub mirrors every published skill into github.com/openclaw/skills
# via the clawdhub[bot] on publish. Pulling from that archive at a pinned
# SHA gives us:
#   * Deterministic builds — same SHA = same skill content forever.
#   * No dependency on clawhub's rate limiter (GitHub Actions runners
#     share IP pools that easily blow past clawhub's 180/15min cap).
#   * One network round-trip for the whole skill set instead of N.
#
# Sparse-checkout + --filter=blob:none keeps the clone lean — we fetch
# only the skill directories we'll copy into /.openclaw/skills/.
#
# Lex runtime naming: the archive paths sometimes carry a `-skill`
# suffix or an author prefix (e.g. skills/openclaw/ffmpeg-skill/). We
# normalize to bare slugs at copy time so the runtime sees clean names.
#
# Kept LAST in the Dockerfile so skill-list bumps don't invalidate the
# ~250MB Chromium layer above.
# -----------------------------------------------------------------------------

# Pin to openclaw/skills main at 2026-04-23T21:02Z. Bump this SHA to
# pick up new skill versions — a SHA change triggers a fresh skill
# layer but leaves every earlier layer cached.
ARG OPENCLAW_SKILLS_SHA=b6b31a72276f8abf29fedc2aeb7ce0aa890897aa

# Create the global skills dir as root (only root can mkdir under /)
# and hand ownership to node.
USER root
RUN mkdir -p /.openclaw/skills \
 && chown -R node:node /.openclaw

USER node
RUN set -e; \
    git clone --filter=blob:none --no-checkout \
      https://github.com/openclaw/skills.git /tmp/openclaw-skills; \
    cd /tmp/openclaw-skills; \
    git sparse-checkout init --cone; \
    git sparse-checkout set \
      skills/matrixy/agent-browser-clawdbot \
      skills/openclaw/apify \
      skills/steipete/blogwatcher \
      skills/openclaw/ffmpeg-skill \
      skills/ivangdavila/market-research \
      skills/peterskoett/self-improving-agent \
      skills/aaron-he-zhu/seo-content-writer \
      skills/openclaw/topic-monitor \
      skills/therohitdas/transcriptapi; \
    git checkout "${OPENCLAW_SKILLS_SHA}"; \
    # Copy each skill to /.openclaw/skills/<bare-slug>, normalizing the
    # upstream path layout to Lex runtime conventions.
    cp -r skills/matrixy/agent-browser-clawdbot   /.openclaw/skills/agent-browser-clawdbot; \
    cp -r skills/openclaw/apify                   /.openclaw/skills/apify; \
    cp -r skills/steipete/blogwatcher             /.openclaw/skills/blogwatcher; \
    cp -r skills/openclaw/ffmpeg-skill            /.openclaw/skills/ffmpeg; \
    cp -r skills/ivangdavila/market-research      /.openclaw/skills/market-research; \
    cp -r skills/peterskoett/self-improving-agent /.openclaw/skills/self-improving-agent; \
    cp -r skills/aaron-he-zhu/seo-content-writer  /.openclaw/skills/seo-content-writer; \
    cp -r skills/openclaw/topic-monitor           /.openclaw/skills/topic-monitor; \
    cp -r skills/therohitdas/transcriptapi        /.openclaw/skills/transcriptapi; \
    # Drop the clone; skills are now at their runtime path.
    rm -rf /tmp/openclaw-skills; \
    # Remove .git directories from the skill dirs (they shouldn't exist
    # after a sparse-checkout copy, but defense in depth).
    find /.openclaw/skills -name .git -type d -exec rm -rf {} +; \
    echo "==> skills baked:"; \
    ls -la /.openclaw/skills/

# -----------------------------------------------------------------------------
# OCI labels for registry legibility.
# -----------------------------------------------------------------------------

ARG IMAGE_VERSION=dev
LABEL org.opencontainers.image.source="https://github.com/Deku-Studios/lex-openclaw-image" \
      org.opencontainers.image.description="Lex-flavored OpenClaw with baked agent tooling, hooks, and globally-scoped skills" \
      org.opencontainers.image.version="${IMAGE_VERSION}" \
      org.opencontainers.image.licenses="UNLICENSED" \
      org.opencontainers.image.vendor="Deku Studios"
