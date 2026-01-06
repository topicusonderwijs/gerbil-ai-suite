#!/bin/bash

# Setup MCP server configuration file
# Runs after devcontainer is created

set -e

ENV_FILE="/workspaces/gerbil_ai_suite/.env"
MCP_DIR="$HOME/.vscode-server/data/User"
MCP_FILE="$MCP_DIR/mcp.json"

echo "🔧 Configuring MCP server in mcp.json..."

# Source environment variables
if [ ! -f "$ENV_FILE" ]; then
    echo "⚠️  Warning: .env file not found at $ENV_FILE"
    echo "   MCP server will be configured but credentials will be empty."
    GRAFANA_URL=""
    GRAFANA_SERVICE_ACCOUNT_TOKEN=""
else
    source "$ENV_FILE"
    echo "✅ Loaded credentials from .env"
fi

# Ensure MCP directory exists
mkdir -p "$MCP_DIR"

# Check if mcp.json exists
if [ -f "$MCP_FILE" ]; then
    echo "📝 Updating existing mcp.json..."
    
    # Backup existing file
    cp "$MCP_FILE" "$MCP_FILE.backup.$(date +%s)"
    
    # Use jq to merge the Grafana server configuration
    if command -v jq &> /dev/null; then
        jq --arg url "$GRAFANA_URL" --arg token "$GRAFANA_SERVICE_ACCOUNT_TOKEN" \
        '.servers.grafana = {
            "type": "stdio",
            "command": "docker",
            "args": [
                "run",
                "-i",
                "--rm",
                "-e",
                ("GRAFANA_URL=" + $url),
                "-e",
                ("GRAFANA_SERVICE_ACCOUNT_TOKEN=" + $token),
                "mcp/grafana",
                "-t",
                "stdio"
            ]
        }' "$MCP_FILE" > "$MCP_FILE.tmp" && mv "$MCP_FILE.tmp" "$MCP_FILE"
        echo "✅ mcp.json updated successfully"
    else
        echo "⚠️  jq not found. Creating new mcp.json (existing file backed up)..."
        cat > "$MCP_FILE" << EOF
{
    "servers": {
        "grafana": {
            "type": "stdio",
            "command": "docker",
            "args": [
                "run",
                "-i",
                "--rm",
                "-e",
                "GRAFANA_URL=$GRAFANA_URL",
                "-e",
                "GRAFANA_SERVICE_ACCOUNT_TOKEN=$GRAFANA_SERVICE_ACCOUNT_TOKEN",
                "mcp/grafana",
                "-t",
                "stdio"
            ]
        }
    }
}
EOF
        echo "✅ mcp.json created successfully"
    fi
else
    echo "📝 Creating new mcp.json..."
    
    cat > "$MCP_FILE" << EOF
{
    "servers": {
        "grafana": {
            "type": "stdio",
            "command": "docker",
            "args": [
                "run",
                "-i",
                "--rm",
                "-e",
                "GRAFANA_URL=$GRAFANA_URL",
                "-e",
                "GRAFANA_SERVICE_ACCOUNT_TOKEN=$GRAFANA_SERVICE_ACCOUNT_TOKEN",
                "mcp/grafana",
                "-t",
                "stdio"
            ]
        }
    }
}
EOF
    echo "✅ mcp.json created successfully"
fi

echo ""
echo "🎉 MCP server configuration complete!"
echo "   You may need to reload VS Code window to activate the MCP server."
echo ""
