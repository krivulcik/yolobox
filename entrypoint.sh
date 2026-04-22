#!/bin/bash
set -e

USER_HOME="/home/${USERNAME}"
TEMPLATE="$USER_HOME/.pi/agent/models.json.template"
TARGET="$USER_HOME/.pi/agent/models.json"

if [ "${INSTALL_PI}" = "true" ] && [ -f "$TEMPLATE" ]; then
    : "${PI_PROVIDER:=local}"
    : "${PI_BASE_URL:=http://localhost:11434}"
    : "${PI_API:=anthropic-messages}"
    : "${PI_API_KEY:=MY_API_KEY}"
    : "${PI_MODEL_ID:=opus}"
    : "${PI_MODEL_NAME:=opus}"
    : "${PI_MODEL_REASONING:=false}"
    : "${PI_CONTEXT_WINDOW:=100000}"
    export PI_PROVIDER PI_BASE_URL PI_API PI_API_KEY PI_MODEL_ID PI_MODEL_NAME PI_MODEL_REASONING PI_CONTEXT_WINDOW

    envsubst < "$TEMPLATE" > "$TARGET"
    chown "${USERNAME}:${USERNAME}" "$TARGET"
    chmod 600 "$TARGET"
fi

exec "$@"
