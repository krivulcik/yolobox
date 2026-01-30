#!/bin/bash

set -e

# Default values
DEFAULT_IMAGE="yoloimage"
DEFAULT_PORT="22222"

usage() {
    echo "Usage: $0 -n <hostname> [-i <image>] [-p <port>]"
    echo ""
    echo "Options:"
    echo "  -n <hostname>  Container hostname and name (required)"
    echo "  -i <image>     Docker image name (default: $DEFAULT_IMAGE)"
    echo "  -p <port>      Host port to map to container port 22 (default: $DEFAULT_PORT)"
    echo ""
    echo "Example: $0 -n yolo-claudecode -p 22222"
    exit 1
}

# Parse arguments
while getopts "n:i:p:h" opt; do
    case $opt in
        n) DOCKERHOSTNAME="$OPTARG" ;;
        i) IMAGE="$OPTARG" ;;
        p) PORT="$OPTARG" ;;
        h) usage ;;
        *) usage ;;
    esac
done

# Validate required parameters
if [ -z "$DOCKERHOSTNAME" ]; then
    echo "Error: hostname (-n) is required"
    usage
fi

# Set defaults if not provided
IMAGE="${IMAGE:-$DEFAULT_IMAGE}"
PORT="${PORT:-$DEFAULT_PORT}"

# Derive workspace path from hostname
WORKSPACE_PATH="$HOME/workspace/$DOCKERHOSTNAME"

echo "Redeploying container: $DOCKERHOSTNAME"
echo "  Image: $IMAGE"
echo "  Port: $PORT -> 22"
echo "  Workspace: $WORKSPACE_PATH"
echo ""

# Stop and remove existing container (ignore errors if container doesn't exist)
echo "Stopping and removing existing container..."
sudo docker stop "$DOCKERHOSTNAME" 2>/dev/null || true
sudo docker rm "$DOCKERHOSTNAME" 2>/dev/null || true

# Run new container
echo "Starting new container..."
sudo docker run -d \
    -p "$PORT:22" \
    -v "$WORKSPACE_PATH:/workspace" \
    --hostname "$DOCKERHOSTNAME" \
    --name "$DOCKERHOSTNAME" \
    "$IMAGE"

echo ""
echo "Container $DOCKERHOSTNAME is now running."
