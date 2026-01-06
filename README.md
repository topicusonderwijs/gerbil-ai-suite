# Gerbil AI Suite

A suite of Model Context Protocol (MCP) servers for AI-related work in VS Code. Docker-based approach for easy setup and cross-platform compatibility.

## 🚀 Quick Start

### Prerequisites

- Docker installed and running
- VS Code with Dev Containers extension
- Git

### Setup

1. Clone this repository:
   ```bash
   git clone <repository-url>
   cd gerbil_ai_suite
   ```

2. Open in VS Code:
   ```bash
   code .
   ```

3. When prompted, click **"Reopen in Container"** (or use Command Palette: `Dev Containers: Reopen in Container`)

4. The setup script will automatically prompt you for:
   - Grafana URL (e.g., `https://your-grafana.com`)
   - Grafana Service Account Token

5. The script tests the connection and creates a `.env` file on your host

6. The devcontainer pulls the official Grafana MCP Docker image

7. The MCP server is automatically configured in `~/.vscode-server/data/User/mcp.json`

8. After setup completes, **reload VS Code window** (`Ctrl+Shift+P` → `Developer: Reload Window`)

9. The Grafana MCP is now available in GitHub Copilot across all workspaces!

## 📦 MCP Servers

### Grafana MCP

Official [Grafana MCP server](https://github.com/grafana/mcp-grafana) providing comprehensive access to Grafana monitoring and observability. Runs via Docker in read-only mode for security.

**Capabilities:**
- Search dashboards, folders, and resources
- Query Prometheus and Loki datasources  
- View alert rules and notification policies
- Access OnCall schedules and alert groups (if plugin installed)
- Retrieve Sift investigations (if plugin installed)
- Execute PromQL and LogQL queries
- View datasource configurations

See the [official documentation](https://github.com/grafana/mcp-grafana) for a complete list of 50+ available tools.

## 🏗️ Project Structure

```
gerbil_ai_suite/
├── .devcontainer/          # Dev container configuration
│   ├── devcontainer.json   # Container setup with MCP auto-config
│   ├── setup-env.sh        # Interactive credential setup script
│   └── setup-mcp.sh        # Automatic MCP configuration script
├── .env.example            # Template for environment variables
├── mcp.json.example        # Template for MCP configuration
├── .gitignore             # Git ignore rules
└── README.md              # This file
```

## 🔄 How Persistence Works

### Container Rebuilds
When you rebuild the container:
- ✅ `.env` file persists (stored in workspace on host)
- ✅ `mcp.json` persists (stored in VS Code Server volume at `~/.vscode-server/data/User/`)
- ✅ MCP server configuration remains intact
- ✅ No need to reconfigure credentials

### Fresh Starts (New Users)
When someone clones the repository:
1. The `initializeCommand` prompts for credentials
2. Creates `.env` file in the workspace
3. The `postCreateCommand` runs `setup-mcp.sh`
4. MCP server is automatically configured in `mcp.json`
5. Ready to use after reloading VS Code

### MCP Configuration File
The MCP server is configured in `~/.vscode-server/data/User/mcp.json`, which:
- Is the official way to configure MCP servers in VS Code
- Works across all your workspaces
- Survives container rebuilds
- Automatically set up for each user
- Separates MCP configuration from other VS Code settings

## 🔒 Security

- Never commit `.env` files (gitignored by default)
- MCP runs in read-only mode (`--disable-write`)
- Use read-only service accounts with minimal permissions
- Regularly rotate service account tokens
- Review MCP server logs for unexpected access patterns

## 🛠️ Configuration

### Service Account Setup

1. Navigate to **Administration** → **Service accounts** in Grafana
2. Click **Add service account**
3. Set name and role: **Viewer** (read-only is sufficient)
4. Click **Create**
5. Click **Add service account token**
6. Copy the token - you'll use this during setup

### Folder Permissions (Optional)

To limit access to specific folders:
1. Go to **Dashboards** → **Browse**
2. Select folder → Settings (gear icon) → **Permissions**
3. Add your service account with **Viewer** role

## 🤝 Adding New MCP Servers

To add more MCP servers to the suite:

1. Update [.devcontainer/devcontainer.json](.devcontainer/devcontainer.json) MCP configuration
2. Add necessary environment variables to [.env.example](.env.example)
3. Update [.devcontainer/setup-env.sh](.devcontainer/setup-env.sh) to collect credentials
4. Update `postCreateCommand` to pull additional Docker images
5. Document the new server in this README

## 💡 Usage Example

When connected to GitHub Copilot:

```
User: Show me all dashboards in the Production folder
AI: [Uses search_dashboards tool]

User: Query the last hour of errors from Loki
AI: [Uses query_loki tool with appropriate LogQL]

User: What are the current alert rules?
AI: [Uses list_alert_rules tool]
```

## 🐛 Troubleshooting

### Setup Script Fails

- Ensure Docker is running
- Check network connectivity to Grafana
- Verify service account token is valid
- Try running setup script manually: `bash .devcontainer/setup-env.sh`

### Connection Test Fails

- Verify `GRAFANA_URL` is correct and accessible
- Check service account token hasn't expired
- Ensure service account has at least Viewer role

### MCP Not Showing in Copilot

- Ensure GitHub Copilot extension is installed and activated
- Restart VS Code after container setup
- Check Docker container is running: `docker ps`
- Verify `.env` file exists and has valid content

### Docker Permission Errors

- Ensure Docker is running
- Verify your user has Docker permissions
- Try `docker pull mcp/grafana` manually

## 📚 Resources

- [Model Context Protocol](https://modelcontextprotocol.io/)
- [Grafana MCP Server](https://github.com/grafana/mcp-grafana)
- [VS Code Dev Containers](https://code.visualstudio.com/docs/devcontainers/containers)
- [GitHub Copilot](https://github.com/features/copilot)

## 📄 License

MIT
