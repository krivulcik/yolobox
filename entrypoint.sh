#!/bin/bash
set -e

USER_HOME="/home/${USERNAME}"
AGENT_DIR="$USER_HOME/.pi/agent"
MODELS_JSON="$AGENT_DIR/models.json"

# --- Align the in-container user with the host user (volume UID/GID consolidation) ---
# Files in the bind-mounted /workspace are owned by whatever UID/GID the container
# user has. If that doesn't match the host user, the host can't read/write the files
# the agent creates (and vice versa). Resolve the target IDs and remap the user
# before anything else touches the volume. Precedence:
#   1. HOST_UID / HOST_GID env (set by docker-compose / yolobox-redeploy.sh), else
#   2. the current owner of the /workspace mount (skipped when root-owned), else
#   3. keep the image default (1000).
CURRENT_UID="$(id -u "${USERNAME}")"
CURRENT_GID="$(id -g "${USERNAME}")"

TARGET_UID="${HOST_UID:-}"
TARGET_GID="${HOST_GID:-}"

if [ -d /workspace ]; then
    WS_UID="$(stat -c '%u' /workspace 2>/dev/null || echo "")"
    WS_GID="$(stat -c '%g' /workspace 2>/dev/null || echo "")"
    [ -z "$TARGET_UID" ] && [ -n "$WS_UID" ] && [ "$WS_UID" != "0" ] && TARGET_UID="$WS_UID"
    [ -z "$TARGET_GID" ] && [ -n "$WS_GID" ] && [ "$WS_GID" != "0" ] && TARGET_GID="$WS_GID"
fi

TARGET_UID="${TARGET_UID:-$CURRENT_UID}"
TARGET_GID="${TARGET_GID:-$CURRENT_GID}"

if [ "$TARGET_GID" != "$CURRENT_GID" ]; then
    echo "entrypoint: remapping ${USERNAME} GID ${CURRENT_GID} -> ${TARGET_GID}"
    groupmod -g "$TARGET_GID" "${USERNAME}" 2>/dev/null \
        || echo "entrypoint: warning - could not set GID ${TARGET_GID} (already in use?)" >&2
fi
if [ "$TARGET_UID" != "$CURRENT_UID" ]; then
    echo "entrypoint: remapping ${USERNAME} UID ${CURRENT_UID} -> ${TARGET_UID}"
    usermod -u "$TARGET_UID" "${USERNAME}" 2>/dev/null \
        || echo "entrypoint: warning - could not set UID ${TARGET_UID} (already in use?)" >&2
fi

# Re-own anything still held by the old IDs: the user's home plus any /workspace
# files written under the previous UID/GID. usermod only rehomes home-dir files by
# UID, so fix the GID and the volume explicitly. Runs only when an actual remap
# happened, to avoid a needless recursive chown on every start.
EFFECTIVE_UID="$(id -u "${USERNAME}")"
EFFECTIVE_GID="$(id -g "${USERNAME}")"
if [ "$EFFECTIVE_UID" != "$CURRENT_UID" ] || [ "$EFFECTIVE_GID" != "$CURRENT_GID" ]; then
    chown -R "${EFFECTIVE_UID}:${EFFECTIVE_GID}" "$USER_HOME" 2>/dev/null || true
    find /workspace -xdev \( -uid "$CURRENT_UID" -o -gid "$CURRENT_GID" \) \
        -exec chown -h "${EFFECTIVE_UID}:${EFFECTIVE_GID}" {} + 2>/dev/null || true
fi

# Ensure the workspace root itself is owned by the (possibly remapped) user.
chown "${USERNAME}:${USERNAME}" /workspace 2>/dev/null || true

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
