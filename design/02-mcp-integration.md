# MCP Integration Design

**Version:** 0.1 (Design)  
**Date:** 2026-02-26  
**Status:** Draft

---

## 1. Context

The existing VS Code workflow uses two MCP servers over `stdio` (subprocess pipes):

| Server | Current command | Transport |
|---|---|---|
| Grafana | `docker run -i --rm mcp/grafana -t stdio` | stdio |
| SmartBear / Bugsnag | `npx -y @smartbear/mcp@latest` | stdio |
| GitHub | VS Code built-in Copilot (no config file) | internal |

In Kubernetes, `stdio` subprocesses in the main container are difficult to manage (no docker-in-docker, no direct npx invocation at scale). This document defines the **hybrid transport strategy** for all three servers.

---

## 2. Transport Decision Matrix

| Server | MVP transport | Rationale |
|---|---|---|
| **Grafana MCP** | HTTP/SSE (separate container/Deployment) | Grafana MCP Docker image supports `-t sse`; runs as a standalone service; no docker-in-docker needed |
| **SmartBear / Bugsnag MCP** | stdio sidecar | `@smartbear/mcp` is an npx package with unknown SSE support; runs as a sidecar container in the same pod |
| **GitHub MCP** | HTTP/SSE (separate Deployment) | `mcp-server-github` (Node.js reference implementation) supports SSE; natural standalone service |

---

## 3. Server Specifications

### 3.1 Grafana MCP (HTTP/SSE — standalone Deployment)

**Image:** `mcp/grafana` (Docker Hub or private mirror)  
**Transport flag:** `-t sse`  
**Port:** `8080` (default SSE port for Grafana MCP)

**Kubernetes Deployment sketch:**

```yaml
containers:
  - name: grafana-mcp
    image: mcp/grafana:latest
    args: ["-t", "sse"]
    ports:
      - containerPort: 8080
    env:
      - name: GRAFANA_URL
        valueFrom:
          secretKeyRef:
            name: grafana-mcp-secret
            key: GRAFANA_URL
      - name: GRAFANA_SERVICE_ACCOUNT_TOKEN
        valueFrom:
          secretKeyRef:
            name: grafana-mcp-secret
            key: GRAFANA_SERVICE_ACCOUNT_TOKEN
```

**LangGraph client config:**

```python
grafana_client = MCPClient(
    transport="sse",
    url="http://grafana-mcp-service.gerbil.svc.cluster.local:8080/sse",
)
```

**Namespace:** `gerbil` (dedicated namespace, see [`07-kubernetes.md`](./07-kubernetes.md))

---

### 3.2 SmartBear / Bugsnag MCP (stdio sidecar via mcp-proxy)

**Package:** `@smartbear/mcp@latest` (npx, Node.js)  
**Transport:** stdio inside the sidecar, exposed as HTTP/SSE to the agent via [mcp-proxy](https://github.com/sparfenyuk/mcp-proxy)  
**Bridge mechanism:** `mcp-proxy` runs as a second process inside the sidecar container. It spawns the SmartBear MCP process over stdio and exposes it as an SSE endpoint on a Unix domain socket. The `gerbil-agent` connects to this socket, making the integration identical to the SSE pattern used for Grafana and GitHub.

This approach was chosen over the alternatives (direct subprocess spawn, shared PID namespace) because it:
- Keeps the Node.js runtime fully isolated in the sidecar — `gerbil-agent` requires only Python.
- Reuses the same `MCPClient(transport="sse")` code path for all three servers.
- Avoids sharing PID namespaces or raw file descriptors across containers.

See [`ADR-005`](./09-adr/adr-005-smartbear-stdio-bridge.md) for the full decision record.

**Sidecar container sketch:**

```yaml
containers:
  - name: smartbear-mcp
    image: ghcr.io/topicusonderwijs/smartbear-mcp-bridge:latest
    # Custom image: node:22-slim + mcp-proxy + @smartbear/mcp
    # Entrypoint: mcp-proxy wraps SmartBear stdio and exposes SSE
    command:
      - mcp-proxy
      - --listen
      - unix:///shared/smartbear.sock
      - --
      - npx
      - "-y"
      - "@smartbear/mcp@latest"
    env:
      - name: BUGSNAG_AUTH_TOKEN
        valueFrom:
          secretKeyRef:
            name: smartbear-mcp-secret
            key: BUGSNAG_AUTH_TOKEN
    volumeMounts:
      - name: mcp-bridge-socket
        mountPath: /shared
```

The `gerbil-agent` container mounts the same `emptyDir` volume:

```yaml
    - name: gerbil-agent
      # ... (other config)
      volumeMounts:
        - name: mcp-bridge-socket
          mountPath: /shared

volumes:
  - name: mcp-bridge-socket
    emptyDir: {}
```

**LangGraph client config:**

```python
smartbear_client = MCPClient(
    transport="sse",
    url="unix:///shared/smartbear.sock/sse",
)
```

> **Note:** The custom bridge image (`smartbear-mcp-bridge`) is built in CI from a simple Dockerfile that installs `mcp-proxy` (Go binary) and `@smartbear/mcp` (npm). If SmartBear publishes native SSE support in a future release, the sidecar can be replaced with a standalone Deployment and the Unix socket bridge removed — no changes to graph nodes required.

---

### 3.3 GitHub MCP (HTTP/SSE — standalone Deployment)

**Package:** `@modelcontextprotocol/server-github` (official MCP reference server)  
**Transport:** HTTP/SSE  
**Port:** `3000` (default)

**Kubernetes Deployment sketch:**

```yaml
containers:
  - name: github-mcp
    image: node:22-slim
    command: ["npx", "-y", "@modelcontextprotocol/server-github@latest"]
    args: ["--transport", "sse", "--port", "3000"]
    env:
      - name: GITHUB_PERSONAL_ACCESS_TOKEN
        valueFrom:
          secretKeyRef:
            name: github-mcp-secret
            key: GITHUB_PERSONAL_ACCESS_TOKEN
    ports:
      - containerPort: 3000
```

**LangGraph client config:**

```python
github_client = MCPClient(
    transport="sse",
    url="http://github-mcp-service.gerbil.svc.cluster.local:3000/sse",
)
```

---

## 4. MCP Client Integration in LangGraph

The LangGraph app uses the [MCP Python SDK](https://github.com/modelcontextprotocol/python-sdk) (`mcp>=1.0`) to manage client sessions.

### 4.1 Client lifecycle

```python
from mcp import ClientSession
from mcp.client.sse import sse_client
from mcp.client.stdio import stdio_client

# Long-lived sessions, initialised once at pod startup:
class MCPRegistry:
    grafana: ClientSession       # SSE
    smartbear: ClientSession     # stdio
    github: ClientSession        # SSE
```

Sessions are kept alive for the pod's lifetime. Reconnection logic handles transient failures.

### 4.2 Tool dispatch

LangGraph tool nodes call `MCPRegistry.<server>.call_tool(name, args)`. The approval wrapper (see [`01-graph-design.md §3.2`](./01-graph-design.md)) intercepts the call before it reaches the registry.

```python
async def execute_mcp_tool(
    state: GerbilBaseState,
    server: str,
    tool_name: str,
    args: dict,
) -> ToolResult:
    """Approval-gated MCP tool executor."""
    if not state["session_consent"]:
        approval = await request_slack_approval(state, server, tool_name, args)
        if approval.rejected:
            return ToolResult(skipped=True)
        if approval.approve_all:
            state["session_consent"] = True

    result = await MCP_REGISTRY[server].call_tool(tool_name, args)
    log_approval(state, tool_name, args, decision="approved")
    return result
```

### 4.3 Tool namespace mapping

| Logical namespace | MCP server | Client |
|---|---|---|
| `grafana/*` | Grafana MCP | `grafana_client` |
| `smartbear/*` | SmartBear MCP | `smartbear_client` |
| `github/*` | GitHub MCP | `github_client` |

---

## 5. Credential Model

All secrets are Kubernetes Secrets projected into environment variables. No secrets are stored in code, ConfigMaps, or container images.

| Secret name | K8s Secret | Keys |
|---|---|---|
| Grafana | `grafana-mcp-secret` | `GRAFANA_URL`, `GRAFANA_SERVICE_ACCOUNT_TOKEN` |
| SmartBear / Bugsnag | `smartbear-mcp-secret` | `BUGSNAG_AUTH_TOKEN`, `BUGSNAG_PROJECT_API_KEY` |
| GitHub | `github-mcp-secret` | `GITHUB_PERSONAL_ACCESS_TOKEN` |
| Slack | `slack-secret` | `SLACK_BOT_TOKEN`, `SLACK_SIGNING_SECRET`, `SLACK_APP_TOKEN` |

See [`08-security.md`](./08-security.md) for rotation policy and least-privilege token scopes.

---

## 6. Failure Modes

| Failure | Behaviour |
|---|---|
| Grafana MCP pod down | Graph node marks phase as DATA_GAP; continues. Slack notification. |
| SmartBear MCP sidecar crash | Pod restarted; in-progress graph resumes from last checkpoint. |
| GitHub MCP pod down | Code Q&A returns error; research graphs skip code-diff steps. |
| SSE connection dropped | Client reconnects with exponential backoff (max 30s, 5 attempts). |
| Credential expired | MCP client returns auth error → Slack alert to Ops → run suspended. |

---

## 7. Known Risks and Mitigations

| Risk | Likelihood | Mitigation |
|---|---|---|
| SmartBear npx doesn't support SSE | High | Stdio sidecar with socket bridge; revisit when SmartBear publishes HTTP transport |
| Grafana MCP SSE port non-standard | Medium | Verify with `docker run mcp/grafana -t sse --help` in spike |
| GitHub MCP SSE not in official package | Low | Reference implementation supports `--transport sse`; verify version pinning |
| Docker Hub rate limits for `mcp/grafana` image | Medium | Mirror to private registry (documented in [`07-kubernetes.md`](./07-kubernetes.md)) |
| Credential rotation breaks running sessions | Low | Sessions reconnect on 401; Health check endpoint for each MCP client |
