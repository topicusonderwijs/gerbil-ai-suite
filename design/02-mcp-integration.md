# MCP Integration Design

**Version:** 0.1 (Design)  
**Date:** 2026-02-26  
**Status:** Draft

---

## 1. Context

The existing VS Code workflow uses two MCP servers over `stdio` (subprocess pipes):

| Server | Current command | Transport |
|---|---|---|
| Grafana | `docker run -i --rm grafana/mcp-grafana -t stdio` | stdio |
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

**Image:** `grafana/mcp-grafana` (Docker Hub)  
**Transport flag:** `-t sse`  
**Port:** `8000` (default SSE port for Grafana MCP)

**Kubernetes Deployment sketch:**

```yaml
containers:
  - name: grafana-mcp
    image: grafana/mcp-grafana:latest
    args: ["-t", "sse"]
    ports:
      - containerPort: 8000
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
    url="http://grafana-mcp-service.gerbil.svc.cluster.local:8000/sse",
)
```

**Namespace:** `gerbil` (dedicated namespace, see [`07-kubernetes.md`](./07-kubernetes.md))

---

### 3.2 SmartBear / Bugsnag MCP (stdio sidecar via mcp-proxy)

**Package:** `@smartbear/mcp@latest` (npx, Node.js)  
**Transport:** stdio inside the sidecar, exposed as HTTP/SSE to the agent via [mcp-proxy](https://github.com/sparfenyuk/mcp-proxy)  
**Bridge mechanism:** `mcp-proxy` runs as a second process inside the sidecar container. It spawns the SmartBear MCP process over stdio and exposes it as an HTTP endpoint on a TCP localhost port (`8081`). Since containers in the same pod share the network namespace, the `gerbil-agent` connects via `http://localhost:8081`, making the integration identical to the HTTP pattern used for Grafana and GitHub.

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
    # Custom image: ghcr.io/sparfenyuk/mcp-proxy (Python) + Node.js + @smartbear/mcp
    # Entrypoint: mcp-proxy wraps SmartBear stdio and exposes SSE
    command:
      - mcp-proxy
      - --host
      - "0.0.0.0"
      - --port
      - "8081"
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
```

No shared volumes are needed — containers in the same pod share the network namespace and the agent connects directly via `localhost:8081`.

**LangGraph client config:**

```python
smartbear_client = MCPClient(
    transport="sse",
    url="http://localhost:8081/sse",
)
```

> **Note:** The custom bridge image (`smartbear-mcp-bridge`) is built in CI from a Dockerfile based on `ghcr.io/sparfenyuk/mcp-proxy:latest` (a Python package, not a Go binary) with Node.js added for `@smartbear/mcp`. If SmartBear publishes native HTTP transport in a future release, the sidecar can be replaced with a standalone Deployment — no changes to graph nodes required.

---

### 3.3 GitHub MCP (HTTP/SSE — standalone Deployment)

**Package:** `ghcr.io/github/github-mcp-server` (official GitHub MCP server — Go binary, not an npm package)  
**Transport:** Streamable HTTP (HTTP transport mode added in v0.x)  
**Port:** `8082` (default; PR #1849 source-verified)

> ✅ **Verified (2025):** The previous spec referenced `@modelcontextprotocol/server-github` (an early Node.js reference implementation). The current official GitHub MCP server is a **Go binary** at `ghcr.io/github/github-mcp-server`. HTTP/Streamable-HTTP mode was added in PR #1849 via the **`http` subcommand** (not a `--transport` flag). Default port is **8082**. The MCP handler is mounted at `/` (root) using `mcp.NewStreamableHTTPHandler`.

**Kubernetes Deployment sketch:**

```yaml
containers:
  - name: github-mcp
    image: ghcr.io/github/github-mcp-server:latest
    args: ["http", "--port", "8082"]
    env:
      - name: GITHUB_PERSONAL_ACCESS_TOKEN
        valueFrom:
          secretKeyRef:
            name: github-mcp-secret
            key: GITHUB_PERSONAL_ACCESS_TOKEN
    ports:
      - containerPort: 8082
```

**LangGraph client config:**

```python
github_client = MultiServerMCPClient(
    {
        "github": {
            "url": "http://github-mcp-service.gerbil.svc.cluster.local:8082",
            "transport": "http",
        }
    }
)
```

---

## 4. MCP Client Integration in LangGraph

The LangGraph app uses [`langchain-mcp-adapters`](https://github.com/langchain-ai/langchain-mcp-adapters) (`langchain-mcp-adapters>=0.1`) to manage MCP sessions and convert MCP tools to LangChain-compatible tool objects.

### 4.1 Client lifecycle

```python
from langchain_mcp_adapters.client import MultiServerMCPClient

# Long-lived client, initialised once at pod startup:
client = MultiServerMCPClient(
    {
        "grafana": {
            "url": "http://grafana-mcp-service.gerbil.svc.cluster.local:8000/mcp",
            "transport": "http",
        },
        "smartbear": {
            "url": "http://localhost:8081/mcp",   # via mcp-proxy sidecar
            "transport": "http",
        },
        "github": {
            "url": "http://github-mcp-service.gerbil.svc.cluster.local:8082",
            "transport": "http",
        },
    }
)
tools = await client.get_tools()
```

> **Note:** The `"http"` transport key is for MCP Streamable HTTP (2025-03-26 spec). Use `"sse"` for legacy SSE servers. The `MultiServerMCPClient` session lifecycle is managed internally; no manual reconnection code is required.

### 4.2 Tool dispatch

LangGraph tool nodes use `ToolNode(tools)` + `tools_condition` from LangGraph prebuilt, where `tools` is the list returned by `client.get_tools()`. The approval wrapper (see [`01-graph-design.md §3.2`](./01-graph-design.md)) intercepts tool calls before the `ToolNode` executes.

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
| SmartBear npx doesn't support SSE | High | Stdio sidecar with TCP mcp-proxy bridge; revisit when SmartBear publishes HTTP transport |
| Grafana MCP SSE port non-standard | Low | Default port is **8000** (verified). Mirror image as `grafana/mcp-grafana` to private registry |
| GitHub MCP HTTP transport flags | ~~Medium~~ Resolved | Verified: subcommand is `http`, default port `8082`, handler mounted at `/` (PR #1849, source-verified) |
| Docker Hub rate limits for `grafana/mcp-grafana` image | Medium | Mirror to private registry (documented in [`07-kubernetes.md`](./07-kubernetes.md)) |
| Credential rotation breaks running sessions | Low | Sessions reconnect on 401; Health check endpoint for each MCP client |
