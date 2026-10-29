# YoloBox

A sandboxed Docker environment for running Claude Code in autonomous mode (`claude --dangerously-skip-permissions`) without risking your host system.

## Why YoloBox?

When using Claude Code's "yolo mode", the AI can execute arbitrary commands without confirmation. YoloBox provides a safe sandbox:

- **Isolated from host**: The container cannot access your host filesystem, home directory, or system files
- **Workspace only**: Only the explicitly mounted `/workspace` directory is accessible
- **Full internet access**: The container can download packages, clone repos, and make API calls
- **Disposable**: Destroy and recreate the container at any time without affecting your host

### Security Model

**What it protects against:**
- Accidental deletion or modification of files outside the workspace
- System-level changes to your host machine
- Access to your host credentials, SSH keys, or config files

**What it does NOT protect against:**
- Data exfiltration (the container has internet access)
- Malicious code reading files within the mounted workspace
- Network-based attacks originating from the container

**Do NOT put credentials inside the container.** This includes API keys, SSH private keys, cloud credentials, or any secrets. If credentials are needed, use environment variables passed at runtime and understand they could potentially be exfiltrated.

## Features

- **Base**: Ubuntu 24.04
- **Node.js**: Latest LTS version
- **.NET**: SDK 10.0
- **Claude Code CLI**: Pre-installed
- **pi-coding-agent** (optional): `@earendil-works/pi-coding-agent` with a body-timeout patch for slow LLM backends — see [pi-coding-agent](#pi-coding-agent-optional)
- **anthropic-no-timeout extension** (optional): Custom Anthropic provider with disabled body timeout for long streaming responses — see [anthropic-no-timeout Extension](#anthropic-no-timeout-extension-optional)
- **SSH Server**: Hardened configuration with key-based authentication only
- **Development Tools**: vim, mc, git, tmux, screen, curl, wget, jq, and more
- **Runs on Docker or WSL containers**: Docker / Docker Compose everywhere, or Windows' built-in `wslc` runtime without Docker Desktop — see [Using WSL Containers on Windows](#using-wsl-containers-on-windows-wslc)

## Build Arguments

| Argument | Default | Description |
|----------|---------|-------------|
| `USERNAME` | `yolo` | The non-root user created in the container |
| `GITHUB_USERNAME` | (empty) | If set, fetches SSH public keys from GitHub for authentication |
| `INSTALL_PI` | `true` | Set to `false` to skip installing `pi-coding-agent`, its patch, and the `anthropic-no-timeout` extension |

## Usage

### Build the Image

```bash
# Basic build
docker build -t yoloimage .

# With GitHub SSH key authentication
docker build --build-arg GITHUB_USERNAME=your-github-username -t yoloimage .

# With custom username
docker build --build-arg USERNAME=myuser --build-arg GITHUB_USERNAME=your-github-username -t yoloimage .
```
Note: If you are using docker compose, the image will be built automatically on `docker compose up` if it doesn't exist. You can also force a rebuild with `docker compose up --build`.

### Run the Container

```bash
# Run with SSH exposed on port 22222
docker run -d -p 22222:22 --name mycontainer yoloimage

# Run with a workspace volume mounted
docker run -d -p 22222:22 -v $(pwd)/workspace:/workspace --name mycontainer yoloimage
```

### Using the Redeploy Script

The `yolobox-redeploy.sh` script simplifies container management by stopping any existing container and starting a fresh one:

```bash
# Basic usage (uses default image 'yoloimage' and port 22222)
./yolobox-redeploy.sh -n my-yolobox

# With custom port
./yolobox-redeploy.sh -n my-yolobox -p 22223

# With custom image
./yolobox-redeploy.sh -n my-yolobox -i mycustomimage

# Show help
./yolobox-redeploy.sh -h
```

The script automatically mounts a workspace directory based on the hostname at `$HOME/workspace/<hostname>`.

### Using Docker Compose

Docker Compose provides an alternative way to manage YoloBox containers with persistent configuration.

#### Quick Start

```bash
# 1. Create your environment file
cp .env.example .env

# 2. Edit .env with your settings (optional, defaults work out of the box)
GITHUB_USERNAME=your_github_username
# CONTAINER_NAME=yolo-claudecode
# DOCKER_IMAGE=yoloimage
# HOST_PORT=22222

# 3. Start the container
docker compose up -d

# 4. Stop and remove the container
docker compose down
```

#### Available Commands

| Action | Command |
|--------|---------|
| Start container in background | `docker compose up -d` |
| Stop and remove container | `docker compose down` |
| Restart container | `docker compose restart` |
| View logs | `docker compose logs -f` |
| Stop without removing | `docker compose stop` |
| Start stopped container | `docker compose start` |

#### Environment Variables

Configure the container by creating a `.env` file or exporting environment variables:

| Variable | Default | Description |
|----------|---------|-------------|
| `COMPOSE_PROJECT_NAME` | `yolo-claudecode` | Compose project name — **must be unique per box** to run multiple simultaneously |
| `CONTAINER_NAME` | `yolo-claudecode` | Container name and hostname |
| `DOCKER_IMAGE` | `yoloimage` | Docker image to use |
| `HOST_PORT` | `22222` | Host port for SSH access |
| `WORKSPACE_PATH` | `$HOME/workspace/$CONTAINER_NAME` | Workspace mount path |

#### Docker Compose vs Redeploy Script

**Use Docker Compose when you want:**
- Persistent configuration in `.env` file
- Standard docker compose workflow
- Easier service management
- Automatic restart on failure
- To add additional services later

**Use the redeploy script when you want:**
- Quick one-off deployments
- To pass parameters directly on command line
- To programmatically manage multiple containers

See [DOCKER_COMPOSE_USAGE.md](DOCKER_COMPOSE_USAGE.md) for more detailed documentation.

### Using WSL Containers on Windows (wslc)

On Windows, `yolobox-wslc.ps1` runs YoloBox with the built-in WSL container runtime
(`wslc`) instead of Docker Desktop. It builds from the same `Dockerfile` and passes the
same build arguments and environment variables as Docker Compose. Configuration lives in
`.env.wsl`.

#### Requirements

- WSL 2.9.3+ with WSL containers (`wsl --update`; check with `wslc --help`)
- Windows PowerShell 5.1 or PowerShell 7

#### Quick Start

```powershell
# 1. Create your environment file
Copy-Item .env.wsl.example .env.wsl

# 2. Edit .env.wsl (GITHUB_USERNAME, WORKSPACE_PATH, LLM_ENDPOINT, ...)

# 3. Build (if needed), start and connect
.\yolobox-wslc.ps1 -Connect
```

#### Available Commands

| Action | Command |
|--------|---------|
| Build image if missing, (re)create container | `.\yolobox-wslc.ps1` |
| Force image rebuild | `.\yolobox-wslc.ps1 -Build` |
| Deploy and SSH in | `.\yolobox-wslc.ps1 -Connect` |
| Stop and remove container (workspace kept) | `.\yolobox-wslc.ps1 -Down` |
| Use a different env file | `.\yolobox-wslc.ps1 -EnvFile .env.other` |
| Don't create or check `%USERPROFILE%\.wslconfig` | `.\yolobox-wslc.ps1 -SkipWslConfig` |
| View logs | `wslc container logs wsl-yolo-claudecode` |
| Shell without SSH | `wslc exec -it wsl-yolo-claudecode su - yolo` |

#### Environment Variables

Same as Docker Compose (including `LLM_*`, `SEARXNG_URL`, `CLAUDE_*` and the `PI_*` build
args), with these WSL-specific defaults:

| Variable | Default | Description |
|----------|---------|-------------|
| `CONTAINER_NAME` | `wsl-yolo-claudecode` | Container name and hostname |
| `DOCKER_IMAGE` | `wsl-yoloimage` | Image name (wslc has its own image store, separate from Docker) |
| `HOST_PORT` | `33333` | Host port for SSH access |
| `APP_PORT` | `4444` | Host port mapped to container port 3000 |
| `WORKSPACE_PATH` | `%USERPROFILE%\workspace\<CONTAINER_NAME>` | Windows path mounted at `/workspace` |

The ports differ from the Docker defaults, so a Docker box and a WSL box can run at the same
time. `host.docker.internal` in any value is rewritten to `host.wslc.internal`. If both boxes
use the same `WORKSPACE_PATH`, they share `/workspace/.home`, which holds the agent logins and
sessions.

#### Connecting from a WSL Distro

wslc publishes ports on Windows' `127.0.0.1`. With default NAT networking, `localhost` inside
a WSL distro (e.g. Ubuntu) is not Windows. On first run, the script creates
`%USERPROFILE%\.wslconfig` with `networkingMode=mirrored`, only if the file doesn't exist, and
offers to run `wsl --shutdown`. After that, `ssh -p 33333 yolo@localhost` works from the distro
too. Without mirrored mode, connect from PowerShell: `ssh -p 33333 yolo@127.0.0.1`.

#### Differences from Docker Compose

- No restart policy: run the script again after a reboot or `wsl --shutdown`
- The first build downloads everything again (images are not shared with Docker)
- Windows only

### Connect via SSH

```bash
ssh -p 22222 yolo@localhost
```

With WSL containers, use port `33333` (or your `HOST_PORT` from `.env.wsl`).

### Run Claude in Yolo Mode

Once connected to the container:

```bash
cd /workspace
claude --dangerously-skip-permissions
```

This allows Claude to execute commands without confirmation prompts, safely contained within the sandbox.

## pi-coding-agent (optional)

[`@earendil-works/pi-coding-agent`](https://www.npmjs.com/package/@earendil-works/pi-coding-agent) is installed globally by default (the project migrated from the now-deprecated `@mariozechner/pi-coding-agent`; see [earendil-works/pi](https://github.com/earendil-works/pi))

### Enabling / disabling

Controlled by the `INSTALL_PI` build arg (default `true`). Set in `.env`:

```bash
INSTALL_PI=false    # skip npm install, skip patch, skip models.json rendering
```

Then rebuild: `docker compose up -d --build` (with WSL containers: `.\yolobox-wslc.ps1 -Build`).

### Configuring Models (Simplified)

The container auto-discovers available models from your LLM server at startup.

**Just set one environment variable:**

```bash
LLM_ENDPOINT=http://127.0.0.1:8001
# or
LLM_ENDPOINT=http://host.docker.internal:11434  # Ollama on host
```

The entrypoint script will:
1. Fetch available models from `{LLM_ENDPOINT}/v1/models`
2. Generate a `work` provider in `~/.pi/agent/models.json` with all discovered models
3. Set its `api` (transport) from `LLM_API` (default `openai-completions`)

**Example `.env`:**

```bash
LLM_ENDPOINT=http://127.0.0.1:8001
# LLM_API=openai-completions            # default; use for OpenAI-compatible servers
# LLM_API=anthropic-no-timeout          # slow Anthropic-Messages endpoint (see below)
```

That's it! After `docker compose up -d`, connect and run:

```bash
ssh -p 22222 yolo@localhost
pi
/model  # Select from auto-discovered models
```

**No LLM_ENDPOINT?** A default placeholder config is created that you can edit manually inside the container.

### anthropic-no-timeout Extension (optional)

`anthropic-no-timeout` is a custom pi **api** (transport), not a provider — it speaks the
Anthropic Messages protocol with undici body/headers timeouts disabled, so a large model on
slow hardware won't trip `UND_ERR_BODY_TIMEOUT` mid-stream. Because pi keys stream handlers by
`api`, any provider can opt in per-endpoint. This lets you mix a fast and a slow backend:

```json
{
  "providers": {
    "work": { "baseUrl": "http://fast:8001",  "api": "openai-completions",   "apiKey": "…", "models": [ … ] },
    "home": { "baseUrl": "http://slow:8001",   "api": "anthropic-no-timeout", "apiKey": "…", "models": [ … ] }
  }
}
```

The target of an `anthropic-no-timeout` model must be **Anthropic Messages-compatible**
(`POST /v1/messages`); OpenAI-compatible servers should use the built-in `openai-completions`.
For a single auto-discovered endpoint, set `LLM_API=anthropic-no-timeout` instead of editing JSON.
Requires `INSTALL_PI=true` (the extension ships in `home/yolo/.pi/agent/extensions/`).

### Manual Configuration (Advanced)

If you need manual control, leave `LLM_ENDPOINT` empty and edit `~/.pi/agent/models.json` inside the container:

```bash
ssh -p 22222 yolo@localhost
vim ~/.pi/agent/models.json
```

See [models.json format](#modelsjson-format) below for the schema.

### Running inside the container

```bash
ssh -p 22222 yolo@localhost
cat ~/.pi/agent/models.json    # view auto-discovered models
cd /workspace
pi                              # launch pi-coding-agent
/model                          # select a model
```

## pi-subagents Extension (optional)

[pi-subagents](https://github.com/MirecX/pi-subagents) registers a `subagent` tool that
dispatches isolated `pi` subprocesses (agents: `scout`, `researcher`, `worker`). It is
**installed from its own repo at build time** (not vendored) — yolobox only owns the
box-specific config generated at runtime. Requires `INSTALL_PI=true`.

Point the build at a fork or pin a version with build args:

```bash
docker build \
  --build-arg PI_SUBAGENTS_REPO=https://github.com/MirecX/pi-subagents \
  --build-arg PI_SUBAGENTS_REF=main \    # branch, tag, or commit SHA
  -t yoloimage .
```

Because subagents run as isolated `pi` processes (spawned with `--no-extensions`), they need
to be told which local model to use and which provider extension to load. The entrypoint
generates `~/.pi/agent/extensions/pi-subagents/config.json` from the same discovery used for
`models.json`:

```json
{
  "maxConcurrency": 4,
  "modelOverride": "work/<discovered-model>",
  "extraExtensions": ["anthropic-no-timeout"]   // only when LLM_API=anthropic-no-timeout
}
```

- `modelOverride` forces every agent onto the box's local model (ignoring the cloud models in
  each agent's frontmatter).
- `extraExtensions` re-adds provider/api extensions into the subagent process so a model on a
  custom api (e.g. `anthropic-no-timeout`) can resolve its provider.

The `researcher`/`worker` agents use `web_search` and `web_fetch`, which are provided by the
pi-searxng extension (below); the entrypoint points pi-subagents' `toolExtensions` at it
automatically. `scout` (read/grep/find/ls) needs no web tools.

## Web search & fetch (pi-searxng extension)

Web tools come from [pi-searxng](https://github.com/MirecX/pi-searxng) (forked and extended
with a `web_fetch` tool), cloned and built at image build (build args `PI_SEARXNG_REPO`/`REF`;
requires `INSTALL_PI=true`). It registers:

- **`web_search`** — queries a [SearXNG](https://github.com/searxng/searxng) instance
- **`web_fetch`** — fetches a page/PDF and extracts clean Markdown (Readability + Turndown,
  `unpdf` for PDFs, optional Jina Reader fallback)

**SearXNG is a shared, external service** — run **one** instance and point every box at it via
`SEARXNG_URL` (no SearXNG is bundled per box). Port **9369** by convention:

```bash
# .env
SEARXNG_URL=http://searxng.lan:9369        # your shared SearXNG on the LAN
```

`web_search` needs a reachable SearXNG; `web_fetch` works with no extra service. Everything
(endpoint, timeouts, size caps, Jina fallback) is configurable — see the
[pi-searxng README](https://github.com/MirecX/pi-searxng).

## Using Claude Code with a Local LLM (optional)

By default Claude Code talks to the hosted Anthropic API. To point it at a local
Anthropic Messages-compatible endpoint instead, set `CLAUDE_LOCAL_LLM=true`. On startup the
entrypoint generates `~/.claude/settings.json` with the right `ANTHROPIC_*` environment:

```bash
# .env
CLAUDE_LOCAL_LLM=true
# Base URL and token default to LLM_ENDPOINT / LLM_API_KEY (shared with pi).
# Override only if Claude Code should use a different endpoint:
# CLAUDE_BASE_URL=http://127.0.0.1:8001    # must NOT include /v1
# CLAUDE_AUTH_TOKEN=sk-...
# CLAUDE_MODEL=my-model                     # if unset, auto-discovered from {base}/v1/models
```

The generated `settings.json` sets `ANTHROPIC_BASE_URL`, `ANTHROPIC_AUTH_TOKEN`, and points
every model slot (`ANTHROPIC_MODEL`, `..._SMALL_FAST_MODEL`, `..._DEFAULT_{OPUS,SONNET,HAIKU}_MODEL`)
at the resolved model. The file is written `0600` and owned by the container user (it holds the
token). Leave `CLAUDE_LOCAL_LLM` unset/`false` to keep Claude Code on the hosted API.

> The target endpoint must speak the **Anthropic Messages** protocol (`POST /v1/messages`).
> This is the same requirement as the `anthropic-no-timeout` pi transport; a litellm proxy in
> front of an OpenAI-compatible server satisfies it.

## SSH Security Notes

- SSH password authentication is disabled
- Root login is disabled
- Only the specified user is allowed to connect
- Public key authentication is required
- The user has passwordless sudo access inside the container

## Exposed Ports

- **22**: SSH server (host `22222` with Docker Compose, `33333` with WSL containers)
- **3000**: Application port (host `4300` with Docker Compose, `4444` with WSL containers)

## Changelog

### 2026-10-29

- **Added WSL containers support for Windows (`yolobox-wslc.ps1`).** Runs YoloBox on the built-in `wslc` runtime without Docker Desktop, using the same `Dockerfile`, build args and env vars, configured via `.env.wsl` (template: `.env.wsl.example`). Defaults to SSH `33333` and app port `4444` so it can run alongside a Docker box, rewrites `host.docker.internal` to `host.wslc.internal`, and on first run creates `.wslconfig` with mirrored networking so SSH works from WSL distros. See [Using WSL Containers on Windows](#using-wsl-containers-on-windows-wslc).

### 2026-07-02

- **Migrated pi to `@earendil-works/pi-coding-agent`.** The `@mariozechner/pi-coding-agent` package is deprecated; the project moved to the `@earendil-works` org ([earendil-works/pi](https://github.com/earendil-works/pi)). Updated the Docker install, the extension imports, and docs.
- **Node bumped to 22.** New pi requires Node `>=22.19.0`; the image now pins the NodeSource major (`setup_${NODE_VERSION}.x`) instead of tracking a drifting LTS.
- **`anthropic-no-timeout` is now a custom `api` (transport), not a provider.** pi keys stream handlers by `api`, so any provider can opt in per-endpoint via `"api": "anthropic-no-timeout"` while keeping its own `baseUrl`/`apiKey` (e.g. `work` → `openai-completions`, `home` → `anthropic-no-timeout`). Added the `LLM_API` env var (default `openai-completions`) to select the generated provider's transport without editing `models.json`.
- **Fixed `models.json` permission bug.** `~/.pi` is a symlink into the persisted `/workspace/.home`, and `chown -R` doesn't traverse a symlinked argument — so the root-written `models.json` stayed `root:root 600` and `pi` (as the container user) got `EACCES`. The entrypoint now chowns the real target. (Affected both transports since the home-persistence feature landed.)
- **Extension hardened against non-conforming proxies.** Switched from the SDK's strict `messages.stream()` accumulator to the raw `messages.create({stream:true})` iterator, so endpoints that violate Anthropic event ordering (e.g. litellm emitting a duplicate `message_start`) no longer fail with "Unexpected event order." Also set `maxTokens` on auto-discovered models (the no-timeout transport derives `max_tokens` from it).
- **Claude Code + local LLM.** Added `CLAUDE_LOCAL_LLM` (gate) — when `true`, the entrypoint generates `~/.claude/settings.json` pointing Claude Code at a local Anthropic Messages endpoint. Base URL/token default to `LLM_ENDPOINT`/`LLM_API_KEY` (override with `CLAUDE_BASE_URL`/`CLAUDE_AUTH_TOKEN`); the model is taken from `CLAUDE_MODEL` or auto-discovered. See [Using Claude Code with a Local LLM](#using-claude-code-with-a-local-llm-optional).
- **Added the pi-subagents extension.** Installed from [its repo](https://github.com/MirecX/pi-subagents) at build time (build args `PI_SUBAGENTS_REPO`/`PI_SUBAGENTS_REF`), not vendored. The entrypoint generates its `config.json` (`modelOverride`, `extraExtensions`, `toolExtensions`) from the discovered model + transport so subagents run on the local LLM. See [pi-subagents Extension](#pi-subagents-extension-optional).
- **Added web search & fetch via [pi-searxng](https://github.com/MirecX/pi-searxng)** (forked + extended with a `web_fetch` tool: Readability/Turndown/PDF/Jina). Cloned and built at image build (`PI_SEARXNG_REPO`/`PI_SEARXNG_REF`). SearXNG is a **shared external instance** pointed at via `SEARXNG_URL` (port `9369` by convention) — one instance serves many boxes. pi-subagents' `researcher`/`worker` are wired to these tools automatically. See [Web search & fetch](#web-search--fetch-pi-searxng-extension).
