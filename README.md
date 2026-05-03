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
- **pi-coding-agent** (optional): `@mariozechner/pi-coding-agent` with a body-timeout patch for slow LLM backends — see [pi-coding-agent](#pi-coding-agent-optional)
- **anthropic-no-timeout extension** (optional): Custom Anthropic provider with disabled body timeout for long streaming responses — see [anthropic-no-timeout Extension](#anthropic-no-timeout-extension-optional)
- **SSH Server**: Hardened configuration with key-based authentication only
- **Development Tools**: vim, mc, git, tmux, screen, curl, wget, jq, and more

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

### Connect via SSH

```bash
ssh -p 22222 yolo@localhost
```

### Run Claude in Yolo Mode

Once connected to the container:

```bash
cd /workspace
claude --dangerously-skip-permissions
```

This allows Claude to execute commands without confirmation prompts, safely contained within the sandbox.

## pi-coding-agent (optional)

[`@mariozechner/pi-coding-agent`](https://www.npmjs.com/package/@mariozechner/pi-coding-agent) is installed globally by default

### Enabling / disabling

Controlled by the `INSTALL_PI` build arg (default `true`). Set in `.env`:

```bash
INSTALL_PI=false    # skip npm install, skip patch, skip models.json rendering
```

Then rebuild: `docker compose up -d --build`.

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
2. Generate `~/.pi/agent/models.json` with all discovered models
3. Use the `anthropic-no-timeout` provider for compatibility

**Example `.env`:**

```bash
LLM_ENDPOINT=http://127.0.0.1:8001
```

That's it! After `docker compose up -d`, connect and run:

```bash
ssh -p 22222 yolo@localhost
pi
/model  # Select from auto-discovered models
```

**No LLM_ENDPOINT?** A default placeholder config is created that you can edit manually inside the container.

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

### models.json Format

```json
{
  "providers": {
    "llm-endpoint": {
      "baseUrl": "http://i127.0.0.1:8001",
      "api": "anthropic",
      "apiKey": "not-needed-for-local",
      "models": [
        {
          "id": "Qwen/Qwen2.5-72B-Instruct",
          "name": "Qwen2.5-72B-Instruct",
          "reasoning": false,
          "input": ["text", "image"],
          "cost": { "input": 0, "output": 0, "cacheRead": 0, "cacheWrite": 0 },
          "contextWindow": 131072
        }
      ]
    }
  }
}
```

| Field | Description |
|-------|-------------|
| `baseUrl` | LLM server URL **without** `/v1` suffix (Anthropic SDK adds it) |
| `api` | Use `"anthropic"` - supported by vLLM and LM Studio |
| `api` | API type: `anthropic` (recommended), `openai-completions`, etc. |
| `apiKey` | API key (not needed for local servers) |
| `models[].id` | Model identifier sent to the API |
| `models[].name` | Display name in pi |
| `models[].reasoning` | `true` if model supports thinking/reasoning |
| `models[].contextWindow` | Maximum context tokens |
| `models[].maxTokens` | Maximum output tokens |

## anthropic-no-timeout Extension

The `anthropic-no-timeout` extension is installed by default (when `INSTALL_PI=true`). It provides:

1. **Default provider for auto-discovered models** - All models from `LLM_ENDPOINT` use this provider
2. **Disabled body timeout** - Prevents `UND_ERR_BODY_TIMEOUT` errors during long streaming responses

### Why This Extension?

Node.js's built-in fetch (undici) has a default body timeout of 300 seconds (5 minutes). When an LLM streams tool-call arguments, some providers buffer the entire JSON and flush it at the end, creating data gaps that exceed 5 minutes and trigger timeout errors.

This extension is used by default for all auto-discovered models (via `api: "anthropic"` in models.json).

### Usage

#### With Local Anthropic-Compatible Servers (Auto-Discovery)

For local models (vLLM, LM Studio, etc.), simply set `LLM_ENDPOINT` in your `.env`:

```bash
LLM_ENDPOINT=http://127.0.0.1:8001
```

The container auto-discovers all models and configures them to use the `anthropic-no-timeout` provider. No manual configuration needed!

```bash
docker compose up -d
ssh -p 22222 yolo@localhost
pi
/model  # All discovered models available
```

#### With Local Servers (Manual Configuration)

If you need to manually configure models (e.g., custom settings per model), edit `~/.pi/agent/models.json` inside the container:

```bash
ssh -p 22222 yolo@localhost
vim ~/.pi/agent/models.json
```

See [models.json Format](#modelsjson-format) above.

### Enabling / Disabling

Controlled by the `INSTALL_PI` build arg (the extension requires pi-coding-agent):

```bash
INSTALL_PI=false    # skip pi-coding-agent, skip extension
```

Then rebuild: `docker compose up -d --build`.

### Development Workflow

Extension source code lives in `extensions/` and is seeded to `home/yolo/.pi/agent/extensions/` for the Docker build.

**To modify the extension:**

1. Edit files in `extensions/anthropic-no-timeout/`
2. Sync to the home seed folder:
   ```bash
   ./sync-extensions.sh
   ```
3. Rebuild the container:
   ```bash
   docker compose up -d --build
   ```

## SSH Security Notes

- SSH password authentication is disabled
- Root login is disabled
- Only the specified user is allowed to connect
- Public key authentication is required
- The user has passwordless sudo access inside the container

## Exposed Ports

- **22**: SSH server
