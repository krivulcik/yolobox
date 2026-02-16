# Docker Compose Usage

This directory contains Docker Compose configuration as an alternative to the `yolobox-redeploy.sh` script.

## Files

- `docker-compose.yml` - Main compose file with environment variable support
- `docker-compose.yml.template` - Annotated template with examples
- `.env.example` - Example environment configuration

## Quick Start

### 1. Create your environment file

```bash
cp .env.example .env
```

Edit `.env` to customize:
```bash
CONTAINER_NAME=yolo-claudecode
DOCKER_IMAGE=yoloimage
HOST_PORT=22222
```

### 2. Start the container

```bash
docker compose up -d
```

### 3. Stop the container

```bash
docker compose down
```

## Commands

| Action | Command |
|--------|---------|
| Start container | `docker compose up -d` |
| Stop and remove | `docker compose down` |
| Restart | `docker compose restart` |
| View logs | `docker compose logs -f` |
| Rebuild | `docker compose up -d --build` |
| Stop only | `docker compose stop` |

## Comparison with yolobox-redeploy.sh

### Bash Script
```bash
./yolobox-redeploy.sh -n yolo-claudecode -i yoloimage -p 22222
```

### Docker Compose
```bash
# Set environment variables
export CONTAINER_NAME=yolo-claudecode
export DOCKER_IMAGE=yoloimage
export HOST_PORT=22222

# Or use .env file and just run:
docker compose up -d
```

## Advantages of Docker Compose

1. **Persistent configuration** - Settings stored in `.env` file
2. **Easier management** - Standard docker compose commands
3. **Better for multiple services** - Can add more services easily
4. **Restart policies** - Automatic restart on failure
5. **No need for sudo** - If user is in docker group

## Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `CONTAINER_NAME` | yolo-claudecode | Container name and hostname |
| `DOCKER_IMAGE` | yoloimage | Docker image to use |
| `HOST_PORT` | 22222 | Host port for SSH access |
| `WORKSPACE_PATH` | `$HOME/workspace/$CONTAINER_NAME` | Workspace mount path |
