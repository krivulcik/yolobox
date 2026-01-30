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
- **SSH Server**: Hardened configuration with key-based authentication only
- **Development Tools**: vim, mc, git, tmux, screen, curl, wget, jq, and more

## Build Arguments

| Argument | Default | Description |
|----------|---------|-------------|
| `USERNAME` | `yolo` | The non-root user created in the container |
| `GITHUB_USERNAME` | (empty) | If set, fetches SSH public keys from GitHub for authentication |

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

## SSH Security Notes

- SSH password authentication is disabled
- Root login is disabled
- Only the specified user is allowed to connect
- Public key authentication is required
- The user has passwordless sudo access inside the container

## Exposed Ports

- **22**: SSH server
