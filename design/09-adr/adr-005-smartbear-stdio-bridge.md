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
| D: mcp-proxy on Unix domain socket | [mcp-proxy](https://github.com/sparfenyuk/mcp-proxy) runs inside the sidecar, wraps SmartBear's stdio transport, and exposes it as HTTP/SSE on a Unix domain socket via a shared `emptyDir` volume | Node.js isolated; agent uses same SSE client for all three servers; mcp-proxy is an established tool | Requires a custom sidecar image; adds one dependency (mcp-proxy Go binary) |

---

## Decision

**Option D: mcp-proxy on a Unix domain socket.**

Architecture:

```
gerbil-agent container                   smartbear-mcp sidecar container
┌─────────────────────┐                 ┌──────────────────────────────┐
│  MCPClient           │                 │  mcp-proxy                   │
│  (transport="sse")   │──── UDS ───────►│  (listens on unix socket)    │
│                      │  /shared/       │         │                    │
│                      │  smartbear.sock │         ▼                    │
└─────────────────────┘                 │  SmartBear MCP (stdio)       │
                                        │  npx @smartbear/mcp@latest   │
                                        └──────────────────────────────┘

Shared volume: emptyDir{} mounted at /shared in both containers
```

### Implementation details

1. **Custom sidecar image:** `ghcr.io/topicusonderwijs/smartbear-mcp-bridge` — built from `node:22-slim` with `mcp-proxy` (Go binary, statically linked) and `@smartbear/mcp` pre-installed.
2. **Entrypoint:** `mcp-proxy --listen unix:///shared/smartbear.sock -- npx -y @smartbear/mcp@latest`
3. **Agent client:** `MCPClient(transport="sse", url="unix:///shared/smartbear.sock/sse")` — identical pattern to Grafana and GitHub clients.
4. **Shared volume:** `emptyDir: {}` named `mcp-bridge-socket`, mounted at `/shared` in both the `gerbil-agent` and `smartbear-mcp` containers.

---

## Rationale

- **Uniform client code:** All three MCP servers are accessed via `MCPClient(transport="sse")`. No special-case stdio handling in the agent.
- **Runtime isolation:** Node.js stays in the sidecar; the `gerbil-agent` image is pure Python.
- **Proven tool:** `mcp-proxy` is actively maintained and designed for exactly this stdio↔SSE bridging use case.
- **Simple upgrade path:** If SmartBear publishes native SSE support, the sidecar can be replaced with a standalone Deployment and the Unix socket swapped for an HTTP ClusterIP Service — zero changes to graph nodes or `MCPRegistry`.
- **No PID namespace sharing or custom pipe wrappers** — avoids fragile mechanisms that break under security policies.

---

## Consequences

- A new Docker image (`smartbear-mcp-bridge`) must be built and maintained in CI. The Dockerfile is minimal (~10 lines).
- `mcp-proxy` becomes a dependency. It is a single Go binary with no transitive dependencies; version should be pinned.
- The `gerbil-agent` pod gains a shared `emptyDir` volume (`mcp-bridge-socket`). This volume is ephemeral and contains only the Unix socket file.
- Health check for SmartBear should verify the socket file exists and the SSE endpoint responds, matching the existing health check pattern in `MCPRegistry`.

---

## Review Trigger

Revisit if:
- SmartBear publishes native HTTP/SSE transport (eliminate the sidecar entirely).
- `mcp-proxy` is abandoned or introduces breaking changes (evaluate alternatives: `socat`, custom Go wrapper).
- Performance testing shows Unix domain socket overhead is significant (unlikely; UDS is zero-copy on Linux).
