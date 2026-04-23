# lex-openclaw-image

Lex-flavored [OpenClaw](https://openclaw.ai) container image. Ships the upstream OpenClaw runtime plus baked-in agent tooling, hooks, and globally-scoped skills so Lex instances boot with a full toolbelt out of the gate.

Published as `ghcr.io/deku-studios/lex-openclaw-image:<tag>` (private). Downstream consumers in `lex-platform` pin by immutable digest, not tag.

## What's baked in

**Base**: `ghcr.io/openclaw/openclaw:2026.4.22` (pinned — we smoke-test upstream bumps on a throwaway tag first).

**Static binaries** (`/usr/local/bin`):
- `gog` (gogcli v0.12.0)
- `op` (1Password CLI v2.30.3)
- `gh` (GitHub CLI v2.89.0)
- `blogwatcher` (v0.0.2)
- `yt-dlp` (2025.01.26)
- `ffmpeg` (BtbN latest static build)

**Node globals** (system-wide `/usr/local`):
- `clawhub`
- `@google/gemini-cli` → `gemini`
- `@anthropic-ai/claude-code` → `claude`
- `@xdevplatform/xurl` → `xurl`
- `agent-media-cli` → `agent-media`
- `@tobilu/qmd` → `qmd`
- `@playwright/test` → `playwright` (+ Chromium via `playwright install --with-deps`)

**Wrappers**:
- `/usr/local/bin/memo` — Tailscale SSH into alex-mac-mini for Apple Notes CLI.

**Hooks** (`/home/node/.openclaw/hooks/`):
- `lex-telemetry` — fans OpenClaw gateway events into the Lex platform firehose. Sourced from `Deku-Studios/lex-telemetry` as a git submodule.

**Globally-scoped skills** (`/home/node/.openclaw/skills/`, installed via `clawhub install`):
- `agent-browser-clawdbot`
- `apify`
- `blogwatcher`
- `ffmpeg`
- `market-research`
- `market-strategy-pmm`
- `memelord`
- `playwright-cli-openclaw`
- `self-improving-agent`
- `seo-content-writer`
- `topic-monitor`
- `transcriptapi`

## What's NOT baked in (stays as runtime bind mounts)

These are per-instance or per-customer — binding them at container `docker run` time is correct:

| Thing | Path | Notes |
|---|---|---|
| 1Password service-account token | `/home/node/.openclaw/credentials/op-token` | used to refresh agent-media key at boot |
| gogcli config + encrypted keyring | `/home/node/.openclaw/gogcli/` | copied to `~/.config/gogcli/` at boot |
| xurl config | `/home/node/.openclaw/.xurl` | copied to `~/.xurl` at boot |
| memo SSH key | `/home/node/.openclaw/.ssh/lex_ed25519` | never baked |
| per-agent skill overlays | `/lex/instances/<slug>/skills/` | customer-installed skills layer on top of global set |

## Repo layout

```
lex-openclaw-image/
  Dockerfile                # multi-stage, layered for cache efficiency
  .dockerignore
  .gitignore
  .gitmodules               # pulls in hooks/lex-telemetry
  hooks/
    lex-telemetry/          # submodule → Deku-Studios/lex-telemetry @ pinned commit
  scripts/
    memo                    # Tailscale SSH wrapper; no secrets baked in
  .github/
    workflows/
      release.yml           # tag push v*.*.* → build + push to GHCR + digest in step summary
      smoke.yml             # PR → build only, no push
  README.md
  CHANGELOG.md
  VERSION                   # read by release.yml; must match the git tag
```

## First-time repo setup (Alex)

The scaffold was generated in `/Users/alex/Documents/Lex/lex-software/lex-openclaw-image/`. To push it to GitHub and cut the v0.1.0 release:

```bash
cd /Users/alex/Documents/Lex/lex-software/lex-openclaw-image

# 1. Create the .gitmodules file. The automated scaffold couldn't write
#    it directly due to dotfile write protection in Cowork mode.
cat > .gitmodules <<'EOF'
[submodule "hooks/lex-telemetry"]
	path = hooks/lex-telemetry
	url = git@github.com:Deku-Studios/lex-telemetry.git
	branch = main
EOF

# 2. Initialize git + add the submodule.
git init
git branch -m main
git submodule add git@github.com:Deku-Studios/lex-telemetry.git hooks/lex-telemetry

# 3. First commit.
git add -A
git commit -m "Initial scaffold: lex-openclaw-image v0.1.0"

# 4. Create the empty private repo on GitHub at Deku-Studios/lex-openclaw-image
#    via the GitHub UI, then:
git remote add origin git@github.com:Deku-Studios/lex-openclaw-image.git
git push -u origin main
```

## GitHub Actions secrets

The workflows need one secret on the `Deku-Studios/lex-openclaw-image` repo (Settings → Secrets → Actions):

- **`SUBMODULE_READ_TOKEN`** — fine-grained PAT with **Contents: Read** on `Deku-Studios/lex-telemetry` (and any other private submodule this repo later adopts). The default `GITHUB_TOKEN` only sees the current repo, which breaks private-submodule checkouts.

The release workflow also uses `GITHUB_TOKEN` to push to GHCR, but that's built in — no secret needed.

## Cutting a release

```bash
# 1. Bump VERSION (semver, no leading 'v').
echo "0.1.1" > VERSION

# 2. Update CHANGELOG.md with an entry under [Unreleased], then rename
#    [Unreleased] → [0.1.1] - <today> and add a fresh [Unreleased] section.

# 3. Commit + tag.
git add VERSION CHANGELOG.md
git commit -m "Bump to 0.1.1"
git tag v0.1.1
git push origin main --tags
```

Pushing the tag triggers `release.yml`. The workflow verifies `VERSION` matches the tag or fails fast, builds amd64, and pushes:

- `ghcr.io/deku-studios/lex-openclaw-image:v0.1.1`
- `ghcr.io/deku-studios/lex-openclaw-image:latest`

The immutable `sha256:...` digest lands in the GitHub Actions step summary on the run page. **That digest is what lex-platform pins into `Instance.image_digest`** — not the tag.

## Bumping upstream OpenClaw

Upgrading the base image (say `openclaw:2026.4.22` → `openclaw:2026.5.1`):

```bash
# 1. Update the ARG in Dockerfile.
sed -i '' 's/UPSTREAM_TAG=2026.4.22/UPSTREAM_TAG=2026.5.1/' Dockerfile

# 2. Cut a throwaway tag first to smoke-test:
git commit -am "Bump upstream to 2026.5.1"
git tag v0.1.1-rc.1
git push origin main --tags
# Wait for release.yml. Pull the digest and deploy to a throwaway droplet.

# 3. Only after the RC validates, promote:
git tag v0.2.0
git push origin --tags
```

## Bumping a baked skill

Add or remove a skill in the Dockerfile's `clawhub install` line (Layer 7). That layer is last in the Dockerfile precisely so skill bumps don't invalidate the 250MB Chromium layer above. Cut a patch release (`0.1.x`) for skill list changes; minor or major for upstream bumps.

## Local build

```bash
# Build with a throwaway tag for local testing:
docker build \
  --build-arg IMAGE_VERSION=local \
  -t lex-openclaw-image:local \
  .

# Run interactively:
docker run --rm -it lex-openclaw-image:local bash
```

## Consumer pinning (lex-platform)

Downstream pins look like this in lex-platform settings:

```python
OPENCLAW_DEFAULT_IMAGE_TAG = "ghcr.io/deku-studios/lex-openclaw-image:v0.1.0"
```

On first dispatch for an Instance, `apps/provisioning/tasks._build_instance_bundle` resolves that tag to its immutable digest via a GHCR manifest HEAD (using `OPENCLAW_GHCR_READ_TOKEN`), persists the digest onto `Instance.image_digest`, and uses the digest URL for the actual `docker pull` on the droplet. Later tag moves can't reskin existing instances — retries/redeploys use the frozen digest.
