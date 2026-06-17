#!/bin/bash
set -e

# Fix workspace ownership in case the volume was created with different UID/GID
chown ${USERNAME}:${USERNAME} /workspace 2>/dev/null || true

USER_HOME="/home/${USERNAME}"
AGENT_DIR="$USER_HOME/.pi/agent"
MODELS_JSON="$AGENT_DIR/models.json"

# Persist selected home files/dirs on the /workspace volume by symlinking them
# from $USER_HOME into /workspace/.home. /workspace is a host-mounted volume, so
# this can only happen at container start (not during image build).
#
# On first run we seed the persistent copy from whatever was baked into the image
# (e.g. .tmux.conf, .bash_history, .pi, .tmux/tpm), then replace the home path with
# a symlink. On later runs the persistent copy already exists and is reused as-is.
WORKSPACE_HOME="/workspace/.home"
# Files that may not exist until a tool creates them (dangling symlink is fine).
LINK_FILES=(.tmux.conf .claude.json .bash_history)
# Directories: ensure the symlink target exists so tools can write into it.
LINK_DIRS=(.tmux .pi .claude)

link_persisted_item() {
    local item="$1" kind="$2"
    local src="$USER_HOME/$item"
    local dst="$WORKSPACE_HOME/$item"

    if [ ! -e "$dst" ]; then
        if [ -e "$src" ] && [ ! -L "$src" ]; then
            # Seed persistent copy from the image-baked content.
            mv "$src" "$dst"
        elif [ "$kind" = "dir" ]; then
            mkdir -p "$dst"
        fi
    fi

    # Replace any real file/dir/stale symlink in the home dir with the symlink.
    [ ! -L "$src" ] && rm -rf "$src"
    ln -sfn "$dst" "$src"
}

mkdir -p "$WORKSPACE_HOME"
for item in "${LINK_FILES[@]}"; do link_persisted_item "$item" file; done
for item in "${LINK_DIRS[@]}";  do link_persisted_item "$item" dir;  done
chown -R "${USERNAME}:${USERNAME}" "$WORKSPACE_HOME"
for item in "${LINK_FILES[@]}" "${LINK_DIRS[@]}"; do
    chown -h "${USERNAME}:${USERNAME}" "$USER_HOME/$item" 2>/dev/null || true
done

if [ "${INSTALL_PI}" = "true" ]; then
    mkdir -p "$AGENT_DIR"
    
    # LLM_ENDPOINT is the base URL without /v1 (e.g., http://127.0.0.1:8001)
    # We'll auto-discover models from the /v1/models endpoint
    if [ -n "${LLM_ENDPOINT}" ]; then
        # Remove trailing slash if present
        LLM_ENDPOINT="${LLM_ENDPOINT%/}"
        
        echo "entrypoint: fetching models from ${LLM_ENDPOINT}/v1/models"
        
        # Fetch models from OpenAI-compatible endpoint (include API key if provided)
        CURL_ARGS=(--max-time 10 -s "${LLM_ENDPOINT}/v1/models")
        if [ -n "${LLM_API_KEY:-}" ]; then
            CURL_ARGS+=(-H "Authorization: Bearer ${LLM_API_KEY}")
        fi
        MODELS_RESPONSE=$(curl "${CURL_ARGS[@]}" 2>/dev/null || echo "")
        
        if [ -n "${MODELS_RESPONSE}" ] && echo "${MODELS_RESPONSE}" | jq -e '.data' >/dev/null 2>&1; then
            # Successfully fetched models - generate models.json with anthropic-no-timeout provider
            echo "entrypoint: discovered $(echo "${MODELS_RESPONSE}" | jq '.data | length') models"
            
            # Generate models.json with discovered models
            # Using anthropic-no-timeout provider from extension (disabled body timeout)
            # Note: baseUrl does NOT include /v1 - the Anthropic SDK adds it internally
            cat > "$MODELS_JSON" << EOF
{
  "providers": {
    "work": {
      "baseUrl": "${LLM_ENDPOINT}",
      "api": "openai-completions",
      "apiKey": "${LLM_API_KEY:-not-needed-for-local}",
      "models": $(echo "${MODELS_RESPONSE}" | jq '[.data[] | {
        id: .id,
        name: (.id | split("/") | .[-1]),
        reasoning: false,
        input: ["text", "image"],
        cost: { input: 0, output: 0, cacheRead: 0, cacheWrite: 0 },
        contextWindow: (.context_window // 131072)
      }]')
    }
  }
}
EOF
            echo "entrypoint: generated $MODELS_JSON with discovered models"
        else
            echo "entrypoint: warning - failed to fetch models from ${LLM_ENDPOINT}/v1/models" >&2
            echo "entrypoint: check LLM_ENDPOINT is correct, server is running, and API key is valid" >&2
            # Fall through to default config
        fi
    fi
    
    # If models.json doesn't exist yet, create a default config
    if [ ! -f "$MODELS_JSON" ]; then
        echo "entrypoint: could not auto-discover models, creating default config"
        cat > "$MODELS_JSON" << 'EOF'
{
  "providers": {
    "work": {
      "baseUrl": "http://localhost:11434",
      "api": "openai-completions",
      "apiKey": "not-needed",
      "models": [
        {
          "id": "default",
          "name": "Default Model",
          "reasoning": false,
          "input": ["text", "image"],
          "cost": { "input": 0, "output": 0, "cacheRead": 0, "cacheWrite": 0 },
          "contextWindow": 32000,
          "maxTokens": 8192
        }
      ]
    }
  }
}
EOF
        echo "entrypoint: created default $MODELS_JSON - edit to configure your models"
    fi
    
    chown -R "${USERNAME}:${USERNAME}" "$USER_HOME/.pi"
    chmod 600 "$MODELS_JSON"
fi

exec "$@"
