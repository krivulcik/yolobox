#!/bin/bash
set -e

USER_HOME="/home/${USERNAME}"
AGENT_DIR="$USER_HOME/.pi/agent"
TEMPLATE="$AGENT_DIR/models.json.template"
TARGET="$AGENT_DIR/models.json"

if [ "${INSTALL_PI}" = "true" ]; then
    if [ ! -f "$TEMPLATE" ]; then
        echo "entrypoint: INSTALL_PI=true but template missing at $TEMPLATE - models.json NOT generated" >&2
    else
        : "${PI_PROVIDER:=local}"
        : "${PI_BASE_URL:=http://localhost:11434}"
        : "${PI_API:=anthropic-messages}"
        : "${PI_API_KEY:=MY_API_KEY}"
        : "${PI_MODEL_ID:=opus}"
        : "${PI_MODEL_NAME:=opus}"
        : "${PI_MODEL_REASONING:=false}"
        : "${PI_CONTEXT_WINDOW:=100000}"
        export PI_PROVIDER PI_BASE_URL PI_API PI_API_KEY PI_MODEL_ID PI_MODEL_NAME PI_MODEL_REASONING PI_CONTEXT_WINDOW

        mkdir -p "$AGENT_DIR"
        envsubst < "$TEMPLATE" > "$TARGET"
        chown -R "${USERNAME}:${USERNAME}" "$USER_HOME/.pi"
        chmod 600 "$TARGET"
        echo "entrypoint: rendered $TARGET"
    fi
fi

exec "$@"
