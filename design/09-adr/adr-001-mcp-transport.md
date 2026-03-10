# ADR-001: MCP Transport Strategy

**Date:** 2026-02-26  
**Status:** Accepted  
**Deciders:** Gerbil AI Suite team

---

## Context

The existing VS Code workflow connects to MCP servers over `stdio` (subprocess pipes). In Kubernetes, each MCP server must be reachable from the `gerbil-agent` Python process. Three servers are required:

1. **Grafana MCP** — Docker image `grafana/mcp-grafana` (port 8000)
2. **SmartBear / Bugsnag MCP** — npx package `@smartbear/mcp`
3. **GitHub MCP** — Go binary `ghcr.io/github/github-mcp-server` (official server; replaces the old `@modelcontextprotocol/server-github` Node.js reference implementation)

Options considered:

| Option | Description | Pros | Cons |
|---|---|---|---|
| A: All stdio sidecars | Run all three as sidecar containers in the same pod; communicate via stdio bridge | Proven pattern from VS Code; credential isolation | Docker-in-Docker needed for Grafana image in sidecar; pod spec complexity; one pod = one session |
| B: All HTTP/SSE services | Run all three as separate Deployments; communicate via HTTP | Clean separation; independent scaling; no Docker-in-Docker | SmartBear npx support for SSE is unknown; requires verification spike |
| C: Hybrid | Use HTTP/SSE where supported (Grafana, GitHub); stdio sidecar where not (SmartBear) | Best fit for each server's capabilities | Two different integration patterns to maintain |

---

## Decision

**Option C: Hybrid** — HTTP/SSE for Grafana and GitHub MCP; stdio sidecar for SmartBear.

Rationale:
- Grafana MCP has a documented `-t sse` flag and default port 8000 (verified; image is `grafana/mcp-grafana`).
- The official GitHub MCP server (`ghcr.io/github/github-mcp-server`, a Go binary) supports HTTP/Streamable-HTTP transport via the `http` subcommand (default port **8082**); verified from PR #1849 source code.
- SmartBear's `@smartbear/mcp` is an npx package with no documented HTTP transport; stdio sidecar is the safe default.
- Hybrid is more complex than all-one-way but avoids blocking the entire integration on SmartBear SSE support.

---

## Consequences

- **Grafana MCP** runs as a separate Deployment + ClusterIP Service in `gerbil` namespace.
- **GitHub MCP** runs as a separate Deployment + ClusterIP Service in `gerbil` namespace.
- **SmartBear MCP** runs as a sidecar container in the `gerbil-agent` pod; a stdio bridge (socket or direct spawn) connects it to the Python MCP client.
- If SmartBear publishes SSE support in a future version, the sidecar can be promoted to a standalone Deployment without any change to the LangGraph graph nodes.
- A spike task must verify the exact SSE port and flags for both Grafana and GitHub MCP before implementation begins.

---

## Review trigger

Revisit if SmartBear publishes official HTTP/SSE transport support or if the stdio sidecar approach proves unreliable in practice.
