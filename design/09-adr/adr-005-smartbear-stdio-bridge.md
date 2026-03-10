# ADR-005: SmartBear MCP stdio-to-SSE Bridge Mechanism

**Date:** 2026-03-10  
**Status:** Accepted  
**Deciders:** Gerbil AI Suite team

---

## Context

ADR-001 established the hybrid transport strategy: HTTP/SSE for Grafana and GitHub MCP servers, stdio sidecar for SmartBear. However, the sidecar integration mechanism was left underspecified — two contradictory approaches appeared in the design documents:

1. **Subprocess spawn from the agent container** — the `gerbil-agent` Python process spawns `npx @smartbear/mcp@latest` directly, requiring Node.js inside the agent image.
2. **Sidecar with stdio bridge** — SmartBear runs in a separate container; a bridge mechanism exposes its stdio interface to the agent.

These are mutually exclusive. This ADR resolves the ambiguity.

---

## Options Considered

| Option | Description | Pros | Cons |
|---|---|---|---|
| A: Direct subprocess spawn | `gerbil-agent` container includes Node.js and spawns SmartBear via `MCPClient(transport="stdio", command=[...])` | Simple; proven pattern from VS Code | Pollutes Python image with Node.js runtime (~200MB); tight coupling; harder to update SmartBear independently |
| B: Shared PID namespace | Sidecar runs SmartBear; agent attaches to sidecar process's stdin/stdout via `shareProcessNamespace: true` | Node.js isolated | Fragile; requires container PID discovery; not supported by all security policies |
| C: Named pipe via emptyDir | Sidecar reads/writes from a FIFO pipe on a shared `emptyDir` volume; agent connects to the same pipe | Node.js isolated; no PID sharing | Custom pipe wrapper needed; error handling is complex; no existing tooling |
| D: mcp-proxy on TCP localhost | [mcp-proxy](https://github.com/sparfenyuk/mcp-proxy) runs inside the sidecar, wraps SmartBear's stdio transport, and exposes it as HTTP (Streamable HTTP + SSE) on a TCP localhost port. Since all containers in a pod share the network namespace, the agent connects via `http://localhost:8081`. | Node.js isolated; agent uses same HTTP client for all three servers; mcp-proxy is an established Python tool | Requires a custom sidecar image; adds one dependency (mcp-proxy Python package) |

---

## Decision

**Option D: mcp-proxy on TCP localhost.**

Architecture:

```
gerbil-agent container                   smartbear-mcp sidecar container
┌─────────────────────┐                 ┌──────────────────────────────┐
│  MultiServerMCPClient │                 │  mcp-proxy                    │
│  (transport="http")   │── TCP :8081 ──►│  (--host 0.0.0.0 --port 8081) │
│  url=localhost:8081   │  (shared net) │         │                    │
│                      │               │         ▼                    │
└─────────────────────┘                 │  SmartBear MCP (stdio)       │
                                        │  npx @smartbear/mcp@latest   │
                                        └──────────────────────────────┘

All containers in a pod share the network namespace — no shared volumes required.
```

### Implementation details

1. **Custom sidecar image:** `ghcr.io/topicusonderwijs/smartbear-mcp-bridge` — built from `ghcr.io/sparfenyuk/mcp-proxy:latest` (a **Python package**, not a Go binary) with Node.js added via apt for `@smartbear/mcp`.
2. **Entrypoint:** `mcp-proxy --host 0.0.0.0 --port 8081 -- npx -y @smartbear/mcp@latest`
3. **Agent client:** Part of `MultiServerMCPClient` config: `{"url": "http://localhost:8081/mcp", "transport": "http"}` — same HTTP pattern as Grafana and GitHub clients.
4. **No shared volumes needed:** Pod containers share the network namespace; communication is via TCP loopback.

---

## Rationale

- **Uniform client code:** All three MCP servers are accessed via `MultiServerMCPClient` with `transport="http"`. No special-case stdio handling in the agent.
- **Runtime isolation:** Node.js stays in the sidecar; the `gerbil-agent` image is pure Python.
- **Proven tool:** `mcp-proxy` (Python package, `pip install mcp-proxy`) is actively maintained and designed for exactly this stdio↔HTTP bridging use case. It exposes both `/sse` and `/mcp` (Streamable HTTP) endpoints.
- **Simple upgrade path:** If SmartBear publishes native HTTP transport, the sidecar can be replaced with a standalone Deployment and the `localhost:8081` URL swapped for an HTTP ClusterIP Service — zero changes to graph nodes.
- **No volumes, no PID sharing:** TCP loopback is the simplest possible IPC mechanism between pod containers. No emptyDir, no socket files, no security policy concerns.

---

## Consequences

- A new Docker image (`smartbear-mcp-bridge`) must be built and maintained in CI. The Dockerfile is minimal: base `ghcr.io/sparfenyuk/mcp-proxy:latest`, add Node.js, pre-install `@smartbear/mcp`.
- `mcp-proxy` becomes a dependency. It is a Python package (`pip install mcp-proxy`); version should be pinned in the Dockerfile.
- No shared volumes are required. The `mcp-bridge-socket` emptyDir volume referenced in earlier design drafts is **not needed**.
- Health check for SmartBear should verify `http://localhost:8081/health` (or the `/mcp` SSE endpoint) responds, rather than a socket file existence check.

---

## Review Trigger

Revisit if:
- SmartBear publishes native HTTP transport (eliminate the sidecar entirely).
- `mcp-proxy` is abandoned or introduces breaking changes (evaluate alternatives: `socat`-based proxy, custom Python wrapper).
- Performance testing shows TCP loopback overhead is unacceptable (highly unlikely).
