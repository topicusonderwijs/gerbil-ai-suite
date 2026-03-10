# Technology Gaps Research

**Date:** 2026-03-10  
**Context:** Gerbil AI Suite — follow-up research for technology gaps identified during LangGraph study  
**Companion to:** [langgraph-research.md](./langgraph-research.md)

---

## Table of Contents

1. [MCP Python SDK ↔ LangChain Bridge (`langchain-mcp-adapters`)](#1-mcp-python-sdk--langchain-bridge)
2. [MCP Transport Evolution (SSE → Streamable HTTP)](#2-mcp-transport-evolution)
3. [Slack Bolt + LangGraph Async Integration](#3-slack-bolt--langgraph-async-integration)
4. [mcp-proxy Validation](#4-mcp-proxy-validation)
5. [LangGraph Platform vs Self-Hosted Kubernetes](#5-langgraph-platform-vs-self-hosted-kubernetes)
6. [Impact on Design Documents](#6-impact-on-design-documents)

---

## 1. MCP Python SDK ↔ LangChain Bridge

### 1.1 The Problem

The design doc [`02-mcp-integration.md`](./02-mcp-integration.md) uses a fictional `MCPClient(transport="sse")` API that doesn't exist. The real MCP Python SDK (`mcp>=1.0`) uses `ClientSession` with transport-specific context managers. LangGraph uses LangChain-compatible tool objects, not raw MCP sessions.

### 1.2 The Solution: `langchain-mcp-adapters`

LangChain officially publishes [`langchain-mcp-adapters`](https://github.com/langchain-ai/langchain-mcp-adapters) (trust score 9.2) — a lightweight package that bridges MCP tools to LangChain/LangGraph tool objects.

**Install:**
```bash
pip install langchain-mcp-adapters langgraph "langchain[openai]"
```

### 1.3 `MultiServerMCPClient` — Central Abstraction

This is the key class for Gerbil. It connects to **multiple MCP servers simultaneously** and aggregates all their tools into a single list usable by LangGraph:

```python
from langchain_mcp_adapters.client import MultiServerMCPClient
from langgraph.graph import StateGraph, MessagesState, START
from langgraph.prebuilt import ToolNode, tools_condition
from langchain.chat_models import init_chat_model

model = init_chat_model("openai:gpt-4.1")

client = MultiServerMCPClient(
    {
        "grafana": {
            "url": "http://grafana-mcp-service.gerbil.svc.cluster.local:8000/mcp",
            "transport": "http",
        },
        "smartbear": {
            "url": "http://localhost:8081/mcp",  # via mcp-proxy sidecar
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

### 1.4 Supported Transports

`MultiServerMCPClient` supports **four** transport types:

| Transport | Config key | Use case |
|-----------|-----------|----------|
| `stdio` | `command`, `args` | Local subprocess (dev) |
| `sse` | `url`, `headers` | Legacy SSE servers |
| `http` | `url`, `headers` | **Recommended** — MCP Streamable HTTP (2025-03-26 spec); `"streamable_http"` is accepted as an alias |
| `websocket` | `url` | Real-time bidirectional (requires `pip install mcp[ws]`) |

### 1.5 Integration with LangGraph StateGraph

The pattern for Gerbil is straightforward — load tools from all MCP servers and bind them to a LangGraph graph:

```python
tools = await client.get_tools()

def call_model(state: MessagesState):
    response = model.bind_tools(tools).invoke(state["messages"])
    return {"messages": response}

builder = StateGraph(MessagesState)
builder.add_node("call_model", call_model)
builder.add_node("tools", ToolNode(tools))
builder.add_edge(START, "call_model")
builder.add_conditional_edges("call_model", tools_condition)
builder.add_edge("tools", "call_model")
graph = builder.compile()
```

### 1.6 LangGraph API Server Factory Pattern

For deployment (relevant to LangGraph Platform or self-hosted), the `make_graph` factory pattern is used:

```python
# graph.py
import os
from langchain_mcp_adapters.client import MultiServerMCPClient
from langchain.agents import create_agent

async def make_graph():
    client = MultiServerMCPClient({
        "grafana": {
            "url": os.getenv("GRAFANA_MCP_URL"),
            "transport": "http",
            "headers": {"Authorization": f"Bearer {os.getenv('GRAFANA_TOKEN')}"}
        },
        "smartbear": {
            "url": os.getenv("SMARTBEAR_MCP_URL"),
            "transport": "http",
        },
    })
    tools = await client.get_tools()
    agent = create_agent("openai:gpt-4.1", tools)
    return agent

# langgraph.json:
# { "dependencies": ["."], "graphs": { "agent": "./graph.py:make_graph" } }
```

### 1.7 Advanced Features

**Tool interceptors** — inject authentication, retry logic, caching, rate limiting:
```python
client = MultiServerMCPClient(
    {... server configs ...},
    tool_interceptors=[AuthInterceptor(), RateLimitInterceptor()]
)
```

**Callbacks** — real-time logging and progress notifications from MCP servers:
```python
from langchain_mcp_adapters.callbacks import Callbacks, CallbackContext

callbacks = Callbacks(
    on_logging_message=on_logging,
    on_progress=on_progress
)
client = MultiServerMCPClient({...}, callbacks=callbacks)
```

**Explicit session management** — persistent connections for stateful operations:
```python
async with client.session("grafana") as session:
    tools = await load_mcp_tools(session)
    # Multiple operations share the same session
```

### 1.8 Low-Level Alternative: `load_mcp_tools`

If `MultiServerMCPClient` is too opinionated, you can use the raw MCP SDK + the adapter function:

```python
from mcp import ClientSession
from mcp.client.streamable_http import streamablehttp_client
from langchain_mcp_adapters.tools import load_mcp_tools

async with streamablehttp_client("http://localhost:8080/mcp") as (read, write, _):
    async with ClientSession(read, write) as session:
        await session.initialize()
        tools = await load_mcp_tools(session)  # → List[LangChain Tool]
```

### 1.9 Key Takeaway for Gerbil

**Replace the fictional `MCPClient` and `MCPRegistry` classes in `02-mcp-integration.md` with `MultiServerMCPClient`.** This eliminates the need for a custom client wrapper — the adapter handles transport management, tool conversion, and session lifecycle.

---

## 2. MCP Transport Evolution

### 2.1 Timeline

| Version | Date | HTTP Transport |
|---------|------|---------------|
| `2024-11-05` | Nov 2024 | **HTTP+SSE** — two separate endpoints (`/sse` for GET, `/message` for POST) |
| `2025-03-26` | Mar 2025 | **Streamable HTTP** — single endpoint (`/mcp`) supporting POST + optional SSE |
| `draft` | Current | Streamable HTTP with batching, protocol version header, enhanced session management |

### 2.2 What Changed: SSE → Streamable HTTP

The old HTTP+SSE transport (2024-11-05) is now **officially deprecated**. The new Streamable HTTP transport (2025-03-26+) replaces it.

**Key differences:**

| Aspect | Old SSE (2024-11-05) | Streamable HTTP (2025-03-26+) |
|--------|---------------------|-------------------------------|
| Endpoints | Two: `GET /sse` + `POST /message` | **One**: `POST /mcp` + optional `GET /mcp` |
| Client → Server | POST to separate endpoint | POST to MCP endpoint |
| Server → Client | Dedicated SSE stream | SSE within POST response, or optional GET SSE stream |
| Session ID | Not specified | `Mcp-Session-Id` header |
| Stateless mode | Not supported | Supported (server doesn't assign session ID) |
| Resumability | Not specified | Standard: `Last-Event-ID` → `GET /mcp` to resume |
| Batch messages | Not supported | JSON-RPC batching supported |
| Protocol version | Not negotiated via HTTP | `MCP-Protocol-Version` header on all requests |

### 2.3 How Streamable HTTP Works

1. **Client sends**: HTTP POST to `/mcp` with JSON-RPC body, `Accept: application/json, text/event-stream`
2. **Server responds**: Either `Content-Type: application/json` (single response) or `Content-Type: text/event-stream` (SSE stream with response + optional server-initiated messages)
3. **Server-initiated messages**: Client can optionally `GET /mcp` to open an SSE stream for server pushes
4. **Session management**: Server MAY assign `Mcp-Session-Id` on init; client includes it in all subsequent requests
5. **Termination**: Client sends `DELETE /mcp` with session ID to end session

### 2.4 Backwards Compatibility

The spec defines a **fallback protocol** for clients that need to support both old and new servers:

1. POST `InitializeRequest` to server URL
2. If **success** → new Streamable HTTP transport
3. If **4xx error** (400, 404, 405) → fall back to GET on the URL, expect old-style SSE `endpoint` event → use old transport

**Both `langchain-mcp-adapters` and `mcp-proxy` support both transports**, making the transition seamless.

### 2.5 Impact on Gerbil Design

The current design doc (`02-mcp-integration.md`) specifies `SSE` throughout. This needs updating:

- **Grafana MCP**: Check if Docker image supports `-t streamable-http` (likely yes with recent versions; default port is **8000**)
- **SmartBear/Bugsnag MCP**: mcp-proxy now exposes both `/sse` AND `/mcp` endpoints automatically
- **GitHub MCP**: Official server is `ghcr.io/github/github-mcp-server` (Go binary). Streamable HTTP mode was added in a recent release; verify exact transport flags before implementation.

**Recommendation:** Use `"http"` as the transport key in `MultiServerMCPClient` (the documented canonical key for Streamable HTTP). `"streamable_http"` is accepted as an alias but the README was updated to prefer `"http"`. The adapter handles both SSE and Streamable HTTP transparently.

### 2.6 Security Considerations (New in Streamable HTTP)

- Servers **MUST validate `Origin` header** on all connections (DNS rebinding protection)
- Servers running locally **SHOULD bind to `127.0.0.1`** only
- Servers **SHOULD implement authentication** for all connections
- Servers **SHOULD include `X-Accel-Buffering: no`** header for SSE responses (reverse proxy compatibility)

---

## 3. Slack Bolt + LangGraph Async Integration

### 3.1 Slack Bolt Async Architecture

Slack Bolt for Python (`slack-bolt`) provides `AsyncApp` for fully async event handling:

```python
from slack_bolt.app.async_app import AsyncApp
from slack_bolt.adapter.socket_mode.async_handler import AsyncSocketModeHandler

app = AsyncApp(token=os.environ["SLACK_BOT_TOKEN"])

async def main():
    handler = AsyncSocketModeHandler(app, os.environ["SLACK_APP_TOKEN"])
    await handler.start_async()
```

**Transport for Gerbil:** Socket Mode (WebSocket) — no public URL needed, works inside Kubernetes without Ingress.

### 3.2 Key Patterns for Gerbil Integration

#### Message Handling → Graph Invocation

```python
@app.message(re.compile(r"(release report|incident|postmortem)", re.I))
async def handle_request(message, say):
    await say("Starting research... I'll update you as I go.")
    
    # Invoke LangGraph with thread_id = Slack thread timestamp
    thread_id = message.get("thread_ts", message["ts"])
    config = {"configurable": {"thread_id": thread_id}}
    result = await graph.ainvoke(
        {"messages": [HumanMessage(content=message["text"])]},
        config=config,
    )
```

#### Button Interactions → LangGraph `interrupt()` / `Command(resume=...)`

This is the critical bridge for the approval workflow:

```python
# When LangGraph hits interrupt(), the node sends a Slack message with buttons:
@app.action("approve_tool_call")
async def handle_approve(ack, body, say):
    await ack()
    
    thread_id = body["message"]["thread_ts"]
    config = {"configurable": {"thread_id": thread_id}}
    
    # Resume the interrupted graph with approval
    await graph.ainvoke(
        Command(resume={"approved": True, "approve_all": False}),
        config=config,
    )

@app.action("approve_all")
async def handle_approve_all(ack, body, say):
    await ack()
    thread_id = body["message"]["thread_ts"]
    config = {"configurable": {"thread_id": thread_id}}
    
    await graph.ainvoke(
        Command(resume={"approved": True, "approve_all": True}),
        config=config,
    )

@app.action("reject_tool_call")
async def handle_reject(ack, body, say):
    await ack()
    thread_id = body["message"]["thread_ts"]
    config = {"configurable": {"thread_id": thread_id}}
    
    await graph.ainvoke(
        Command(resume={"approved": False}),
        config=config,
    )
```

#### Sending Approval Requests from LangGraph Nodes

```python
from langgraph.types import interrupt

async def approval_gate(state: GerbilBaseState) -> dict:
    """Node that pauses for Slack approval."""
    if state.get("session_consent"):
        return {}  # Skip approval if user already said "approve all"
    
    # This sends a Slack message with buttons (via callback)
    # The interrupt() call suspends the graph until Command(resume=...) is received
    approval = interrupt({
        "type": "tool_approval",
        "tool": state["pending_tool"],
        "server": state["pending_server"],
        "args": state["pending_args"],
    })
    
    if not approval["approved"]:
        return {"skipped_tools": [state["pending_tool"]]}
    
    if approval.get("approve_all"):
        return {"session_consent": True}
    
    return {}
```

### 3.3 Block Kit for Approval Messages

```python
def build_approval_blocks(tool_name, server, args):
    return [
        {
            "type": "section",
            "text": {
                "type": "mrkdwn",
                "text": f"*Tool call approval required*\n"
                        f"Server: `{server}`\n"
                        f"Tool: `{tool_name}`\n"
                        f"Args: ```{json.dumps(args, indent=2)}```"
            }
        },
        {
            "type": "actions",
            "elements": [
                {
                    "type": "button",
                    "text": {"type": "plain_text", "text": "✅ Approve"},
                    "action_id": "approve_tool_call",
                    "style": "primary",
                    "value": json.dumps({"tool": tool_name, "server": server}),
                },
                {
                    "type": "button",
                    "text": {"type": "plain_text", "text": "✅ Approve All"},
                    "action_id": "approve_all",
                    "value": json.dumps({"tool": tool_name, "server": server}),
                },
                {
                    "type": "button",
                    "text": {"type": "plain_text", "text": "❌ Reject"},
                    "action_id": "reject_tool_call",
                    "style": "danger",
                    "value": json.dumps({"tool": tool_name, "server": server}),
                },
            ],
        },
    ]
```

### 3.4 Async Middleware Pattern

Bolt's middleware system can inject shared state (like the LangGraph graph instance):

```python
@app.use
async def inject_graph(context, next):
    context["graph"] = graph  # Compiled LangGraph instance
    context["mcp_client"] = mcp_client  # MultiServerMCPClient
    await next()
```

### 3.5 Critical Timing Constraint

Slack requires acknowledgment (`ack()`) within **3 seconds**. LangGraph operations are long-running. The pattern is:

1. **Acknowledge immediately** — `await ack()`
2. **Run graph asynchronously** — use `asyncio.create_task()` or dispatch to background
3. **Stream updates** — use Slack thread messages for progress

```python
@app.message("release report")
async def handle_release(message, say, ack):
    await ack()  # Must happen within 3 seconds
    
    # Run graph in background
    async def run_graph():
        config = {"configurable": {"thread_id": message["ts"]}}
        async for chunk in graph.astream(
            {"messages": [HumanMessage(content=message["text"])]},
            config=config,
            stream_mode="updates",
        ):
            # Send progress updates to Slack thread
            await say(
                text=f"Processing: {chunk}...",
                thread_ts=message["ts"]
            )
    
    asyncio.create_task(run_graph())
```

### 3.6 Socket Mode vs HTTP Mode

| Feature | Socket Mode | HTTP Mode |
|---------|------------|-----------|
| Public URL needed | No | Yes |
| K8s Ingress needed | No | Yes |
| NAT-friendly | Yes | Requires port forwarding |
| Scaling | Single instance | Multiple replicas |
| Reliability | WebSocket reconnection | HTTP load balancing |

**Recommendation for Gerbil:** Start with **Socket Mode** for MVP (no Ingress complexity). Move to HTTP Mode if horizontal scaling is needed.

---

## 4. mcp-proxy Validation

### 4.1 Overview

[mcp-proxy](https://github.com/sparfenyuk/mcp-proxy) (by sparfenyuk) is a Python tool that bridges MCP servers between transports. It has two operating modes:

- **Mode 1 (stdio→HTTP client):** Connect a local stdio client to a remote SSE/Streamable HTTP server
- **Mode 2 (stdio→HTTP server):** Expose a local stdio MCP server over HTTP (SSE + Streamable HTTP)

**Gerbil uses Mode 2** — wrap the SmartBear stdio process and expose it over HTTP.

### 4.2 Current Status

- **PyPI package:** `mcp-proxy` (installable via `pip`, `uv`, or `pipx`)
- **Docker image:** `ghcr.io/sparfenyuk/mcp-proxy:latest`
- **Trust score:** 7.0 (Context7) — actively maintained
- **Transport support:** stdio ↔ SSE **and** Streamable HTTP (both `/sse` and `/mcp` endpoints)
- **Named servers:** Can proxy multiple stdio servers behind a single HTTP endpoint
- **Python API:** Can be used programmatically, not just CLI

### 4.3 Dual Endpoint Exposure

When mcp-proxy runs in Mode 2 (server), it automatically exposes **both** transports:

| Endpoint | Transport | Description |
|----------|-----------|-------------|
| `GET /sse` | Legacy SSE | For old clients (2024-11-05 protocol) |
| `POST /mcp` | Streamable HTTP | For new clients (2025-03-26+ protocol) |
| `GET /status` | Health check | Returns last activity timestamp and server instances |
| `GET /servers/{name}/sse` | Named server SSE | For named server configurations |
| `POST /servers/{name}/mcp` | Named server HTTP | For named server configurations |

### 4.4 Configuration for Gerbil's SmartBear Sidecar

The design doc's sidecar approach is **validated and simplified**:

```bash
# Mode 2: Expose SmartBear stdio over HTTP
mcp-proxy --host 0.0.0.0 --port 8081 --pass-environment \
  npx -y @smartbear/mcp@latest
```

This exposes:
- `http://localhost:8081/mcp` — Streamable HTTP endpoint
- `http://localhost:8081/sse` — Legacy SSE endpoint
- `http://localhost:8081/status` — Health check

### 4.5 Docker Deployment

Custom Dockerfile for the SmartBear sidecar:

```dockerfile
FROM ghcr.io/sparfenyuk/mcp-proxy:latest

# Install Node.js for npx/SmartBear
RUN python3 -m ensurepip && pip install --no-cache-dir uv
# Add Node.js runtime
RUN apt-get update && apt-get install -y nodejs npm && rm -rf /var/lib/apt/lists/*

ENV PATH="/usr/local/bin:$PATH" \
    UV_PYTHON_PREFERENCE=only-system

ENTRYPOINT ["catatonit", "--", "mcp-proxy"]
```

### 4.6 Named Server Configuration

mcp-proxy can host **multiple MCP servers** behind a single instance using a JSON config:

```json
{
  "mcpServers": {
    "smartbear": {
      "enabled": true,
      "timeout": 60,
      "command": "npx",
      "args": ["-y", "@smartbear/mcp@latest"],
      "env": {
        "BUGSNAG_AUTH_TOKEN": "${BUGSNAG_AUTH_TOKEN}"
      },
      "transportType": "stdio"
    }
  }
}
```

Start with: `mcp-proxy --port 8081 --named-server-config /app/servers.json`

### 4.7 Python API (Alternative to CLI)

```python
import asyncio
from mcp.client.stdio import StdioServerParameters
from mcp_proxy.mcp_server import MCPServerSettings, run_mcp_server

async def main():
    settings = MCPServerSettings(
        bind_host="0.0.0.0",
        port=8081,
        stateless=False,
        allow_origins=["*"],
    )
    default_server = StdioServerParameters(
        command="npx",
        args=["-y", "@smartbear/mcp@latest"],
        env={"BUGSNAG_AUTH_TOKEN": os.getenv("BUGSNAG_AUTH_TOKEN")},
    )
    await run_mcp_server(mcp_settings=settings, default_server_params=default_server)

asyncio.run(main())
```

### 4.8 Design Doc Impact

The current design uses **Unix domain sockets** (`unix:///shared/smartbear.sock/sse`) for the sidecar bridge. The validated approach simplifies this to regular HTTP within the pod:

**Before (design doc):**
```yaml
command: ["mcp-proxy", "--listen", "unix:///shared/smartbear.sock", "--", "npx", ...]
```

**After (validated):**
```yaml
command: ["mcp-proxy", "--host", "0.0.0.0", "--port", "8081", "--pass-environment", "npx", "-y", "@smartbear/mcp@latest"]
```

This eliminates the need for shared `emptyDir` volumes and Unix socket mounts between containers. The agent connects via `http://localhost:8081/mcp` (containers in the same pod share localhost).

### 4.9 Key Finding: No Unix Socket Mode

The documented `mcp-proxy` CLI does **not** show a `--listen unix://` flag. The design doc assumed this capability, but the actual supported modes are:
- TCP HTTP server (`--host`, `--port`)
- stdio client (connecting to remote HTTP servers)

**Recommendation:** Use `--host 127.0.0.1 --port 8081` in the sidecar instead of Unix sockets. Containers in the same pod share the network namespace, so `localhost:8081` is accessible without volume mounts.

---

## 5. LangGraph Platform vs Self-Hosted Kubernetes

### 5.1 What is LangGraph Platform?

LangGraph Platform is a hosted service (via LangSmith) that provides:

- **API server** — REST endpoints for running graphs (`/runs/stream`, etc.)
- **LangGraph Studio** — visual debugger and graph explorer (web UI)
- **Managed infrastructure** — no K8s deployment needed
- **LangGraph SDK** — client library for interacting with deployed graphs

### 5.2 Development Server (`langgraph dev`)

```bash
pip install --upgrade "langgraph-cli[inmem]"
langgraph dev  # Starts local API server + Studio UI
```

This provides:
- API at `http://localhost:2024`
- Studio UI at `https://smith.langchain.com/studio/?baseUrl=http://127.0.0.1:2024`
- API docs at `http://127.0.0.1:2024/docs`

### 5.3 Application Structure for Platform

```
my_agent/
├── graph.py          # Graph definition
├── langgraph.json    # Deployment configuration
└── .env              # Environment variables
```

```json
// langgraph.json
{
  "dependencies": ["langchain_openai", "./my_package"],
  "graphs": {
    "my_agent": "./my_package/graph.py:make_graph"
  },
  "env": "./.env"
}
```

### 5.4 Comparison Table

| Feature | LangGraph Platform (LangSmith) | Self-Hosted K8s (Gerbil design) |
|---------|-------------------------------|--------------------------------|
| **Deployment** | `langgraph deploy` or LangSmith UI | Helm chart + K8s manifests |
| **Infrastructure** | Managed by LangChain Inc. | Managed by Topicus |
| **Scaling** | Automatic | Manual (HPA) |
| **Debugging** | LangGraph Studio (visual) | LangSmith tracing + logs |
| **MCP servers** | Must be reachable from LangSmith cloud | Internal K8s services |
| **Data residency** | LangSmith cloud (US) | On-premises / EU |
| **Cost** | Per-run pricing + LangSmith subscription | Infrastructure cost only |
| **Slack integration** | Custom (via webhooks to LangSmith API) | Native (Socket Mode in same cluster) |
| **Git access** | Via HTTPS + PAT | Via K8s service account or sidecar |
| **Secrets** | LangSmith secrets | K8s Secrets |
| **Checkpointing** | Managed PostgreSQL | Self-managed PostgreSQL |
| **Customization** | Limited to platform constraints | Full control |
| **Latency to MCP** | Internet round-trip to Grafana/Bugsnag | In-cluster (<1ms) |

### 5.5 Decision: Self-Hosted K8s

**LangGraph Platform is NOT suitable for Gerbil** because:

1. **Data residency** — Grafana metrics and Bugsnag errors contain production data. Routing through a US cloud service raises GDPR/data sovereignty concerns.
2. **MCP server access** — Grafana and GitHub MCP servers are internal to Topicus infrastructure. Exposing them to the public internet would require additional security layers.
3. **Latency** — MCP tool calls would traverse the internet instead of staying in-cluster.
4. **Slack integration** — Socket Mode requires a persistent WebSocket from within the network. The Platform would need HTTP mode with public Ingress.
5. **Cost** — Per-run pricing for a high-frequency DevOps tool is unpredictable.

### 5.6 What to Borrow from LangGraph Platform

Even though we deploy self-hosted, the Platform's conventions are valuable:

- **`langgraph.json`** — Use this file format for local development with `langgraph dev` and Studio
- **`make_graph()` factory** — Standard pattern for graph instantiation
- **LangGraph SDK** — Can point at our own API if we expose compatible endpoints
- **LangGraph Studio** — Works with `langgraph dev` locally, useful for development and debugging

**Recommendation:** Structure the project with `langgraph.json` for compatibility. Use `langgraph dev` during development for the Studio debugger. Deploy via custom K8s manifests for production.

### 5.7 Recommended Project Structure

```
gerbil-agent/
├── langgraph.json           # LangGraph config (dev + platform compat)
├── pyproject.toml           # Python project config
├── .env                     # Local env vars
├── src/
│   └── gerbil/
│       ├── __init__.py
│       ├── graph.py         # make_graph() factory
│       ├── state.py         # GerbilBaseState, ReleaseState, IncidentState
│       ├── nodes/
│       │   ├── intake.py    # Parse, classify, plan nodes
│       │   ├── research.py  # Domain research nodes
│       │   ├── approval.py  # Approval gate (interrupt)
│       │   ├── synthesis.py # Report synthesis
│       │   └── output.py    # Git commit, Slack delivery
│       ├── mcp/
│       │   ├── client.py    # MultiServerMCPClient setup
│       │   └── tools.py     # Tool interceptors, callbacks
│       └── slack/
│           ├── app.py       # AsyncApp setup
│           ├── handlers.py  # Message/action handlers
│           └── blocks.py    # Block Kit message builders
├── k8s/
│   ├── deployment.yaml
│   ├── service.yaml
│   └── secrets.yaml
└── tests/
```

---

## 6. Impact on Design Documents

### 6.1 Changes Required to `02-mcp-integration.md`

| Section | Current | Should Be |
|---------|---------|-----------|
| §2 Transport Matrix | SSE everywhere | Streamable HTTP (with SSE fallback) |
| §3.1 Grafana client | `MCPClient(transport="sse", url="...8080/sse")` | `MultiServerMCPClient({"grafana": {"url": "...8000/mcp", "transport": "http"}})` |
| §3.2 SmartBear sidecar | Unix socket + `mcp-proxy --listen unix://` | TCP HTTP + `mcp-proxy --host 0.0.0.0 --port 8081` |
| §3.2 SmartBear client | `MCPClient(transport="sse", url="unix:///shared/smartbear.sock/sse")` | Part of `MultiServerMCPClient` config with `transport="http"` |
| §3.3 GitHub client | `MCPClient(transport="sse", url="...3000/sse")` + old npm package | `ghcr.io/github/github-mcp-server` (Go binary); HTTP mode flags to verify |
| §4 Client Integration | Custom `MCPRegistry` class | `MultiServerMCPClient` from `langchain-mcp-adapters` |
| §4.1 Client lifecycle | Manual `ClientSession` management | Managed by `MultiServerMCPClient` |
| §4.2 Tool dispatch | Custom `execute_mcp_tool()` wrapper | `ToolNode(tools)` + `tools_condition` (LangGraph prebuilt) |

### 6.2 Changes Required to `01-graph-design.md`

- **Approval gate pattern:** Update to use `interrupt()` + `Command(resume=...)` instead of custom approval wrapper
- **Tool dispatch:** Use `ToolNode` + `tools_condition` from LangGraph prebuilt instead of manual dispatch

### 6.3 Changes Required to `07-kubernetes.md`

- **SmartBear sidecar:** Remove `emptyDir` volume and Unix socket mounts; use TCP port instead
- **Health checks:** Add `/status` endpoint from mcp-proxy for readiness probes

### 6.4 New ADR Needed

- **ADR-006: Streamable HTTP as default MCP transport** — document the decision to move from SSE to Streamable HTTP, with backwards compatibility fallback

### 6.5 Validation Status

| Design assumption | Validated? | Notes |
|---|---|---|
| mcp-proxy bridges stdio→SSE | ✅ Yes | Also bridges stdio→Streamable HTTP |
| mcp-proxy supports Unix sockets | ❌ No | Use TCP `--host`/`--port` instead |
| `MCPClient(transport="sse")` exists | ❌ No | Use `MultiServerMCPClient` from `langchain-mcp-adapters` |
| LangGraph tool nodes call MCP directly | ⚠️ Partial | Use `ToolNode(tools)` + `tools_condition` pattern instead |
| Slack Socket Mode for K8s | ✅ Yes | `AsyncSocketModeHandler` works well in containers |
| PostgreSQL checkpointing | ✅ Yes | `PostgresSaver` validated in LangGraph research |
| `thread_id = slack_thread_ts` | ✅ Yes | Standard LangGraph pattern |
| Self-hosted K8s over Platform | ✅ Yes | Data residency and MCP access requirements confirm |
