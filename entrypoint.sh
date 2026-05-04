#!/bin/bash
set -e

USER_HOME="/home/${USERNAME}"
AGENT_DIR="$USER_HOME/.pi/agent"
MODELS_JSON="$AGENT_DIR/models.json"

if [ "${INSTALL_PI}" = "true" ]; then
    mkdir -p "$AGENT_DIR"
    
    # LLM_ENDPOINT is the base URL without /v1 (e.g., http://127.0.0.1:8001)
    # We'll auto-discover models from the /v1/models endpoint
    if [ -n "${LLM_ENDPOINT}" ]; then
        # Remove trailing slash if present
        LLM_ENDPOINT="${LLM_ENDPOINT%/}"
        
        echo "entrypoint: fetching models from ${LLM_ENDPOINT}/v1/models"
        
        # Fetch models from OpenAI-compatible endpoint
        MODELS_RESPONSE=$(curl -s --max-time 10 "${LLM_ENDPOINT}/v1/models" 2>/dev/null || echo "")
        
        if [ -n "${MODELS_RESPONSE}" ] && echo "${MODELS_RESPONSE}" | jq -e '.data' >/dev/null 2>&1; then
            # Successfully fetched models - generate models.json with anthropic-no-timeout provider
            echo "entrypoint: discovered $(echo "${MODELS_RESPONSE}" | jq '.data | length') models"
            
            # Generate models.json with discovered models
            # Using anthropic-no-timeout provider from extension (disabled body timeout)
            # Note: baseUrl does NOT include /v1 - the Anthropic SDK adds it internally
            cat > "$MODELS_JSON" << EOF
{
  "providers": {
    "anthropic-no-timeout": {
      "baseUrl": "${LLM_ENDPOINT}",
      "api": "anthropic",
      "apiKey": "not-needed-for-local",
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
            echo "entrypoint: check LLM_ENDPOINT is correct and server is running" >&2
            # Fall through to default config
        fi
    fi
    
    # If models.json doesn't exist yet, create a default config
    if [ ! -f "$MODELS_JSON" ]; then
        echo "entrypoint: no LLM_ENDPOINT set, creating default config"
        cat > "$MODELS_JSON" << 'EOF'
{
  "providers": {
    "llm-endpoint": {
      "baseUrl": "http://localhost:11434",
      "api": "anthropic",
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
