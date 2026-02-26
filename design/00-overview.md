# Gerbil AI Suite — LangGraph/Slack/Kubernetes: System Overview

**Version:** 0.1 (Design)  
**Date:** 2026-02-26  
**Status:** Draft

---

## 1. Purpose

The **Gerbil AI Suite** is an AI-assisted DevOps research platform for the Somtoday school administration platform (Topicus). Its primary consumers are the Ops and Engineering teams who need fast, evidence-based answers about production health, recent releases, and code changes.

This document defines the scope, use cases, success criteria, non-goals, and system-level architecture for the next evolution of the suite: a persistent, Kubernetes-hosted LangGraph application driven by Slack.

---

## 2. Current State

The existing suite runs as a **VS Code GitHub Copilot workspace**:

| Component | Location | Role |
|---|---|---|
| `release_rapport.agent.md` | `.github/agents/` | 8-phase release report workflow |
| `incident_analysis.agent.md` | `.github/agents/` | 8-phase postmortem investigation workflow |
| `copilot-instructions.md` | `.github/` | Domain knowledge: PromQL, dashboard UIDs, Bugsnag project IDs, deployment integrity rules |
| `template/release_rapport.md` | `template/` | Final report output schema |
| `template/postmortem.md` | `template/` | Final postmortem output schema |
| `rapports/` | workspace root | Versioned artifact store (Git) |
| `mcp.json.example` | workspace root | MCP server configuration (Grafana stdio, SmartBear stdio) |

### Limitations of the current model

- Requires a VS Code window; cannot run autonomously or over long periods.
- Single-user: no concurrent execution.
- No Slack integration; output delivery is manual.
- No confirmation or approval loop; the agent acts immediately.
- MCP servers are local subprocesses; cannot be shared across sessions.

---

## 3. Target State

A **LangGraph-based orchestration service** running in Kubernetes that:

1. Accepts work requests from Slack (mentions, slash commands, DMs).
2. Clarifies ambiguous requests interactively before proceeding.
3. Confirms its execution plan with the operator and gets per-tool-call approval (with optional session-wide delegation).
4. Executes multi-phase research using Grafana, Bugsnag, and GitHub MCP servers.
5. Writes incremental research artifacts to Git and posts progress and summaries to Slack.
6. Supports four primary use cases (see §4).

---

## 4. Use Cases

### UC-1: Production Issue Research

> "There's a latency spike on ws-rest — investigate."

- Sources: Grafana (Prometheus + Wildfly metrics), Bugsnag errors, GitHub commits.
- Produces: `rapports/postmortem_YYYY-MM-DD_TITLE/` with research files + summary.
- Template: [`template/postmortem.md`](../template/postmortem.md).
- Follows: 8-phase Incident Analyst workflow from [`incident_analysis.agent.md`](../.github/agents/incident_analysis.agent.md).

### UC-2: Release Report

> "Generate a release report for 16.7."

- Sources: GitHub tags/commits (`topicusonderwijs/iridium`), Grafana production metrics, Bugsnag stability scores.
- Produces: `rapports/release_YYYY-MM-DD_VERSION/` with research files + summary.
- Template: [`template/release_rapport.md`](../template/release_rapport.md).
- Follows: 8-phase Release Reporter workflow from [`release_rapport.agent.md`](../.github/agents/release_rapport.agent.md).

### UC-3: Code and Application Q&A

> "What changed in the authenticator between 16.5 and 16.7?"

- Sources: GitHub MCP (`topicusonderwijs/iridium` — git diff, search, PR list).
- Produces: conversational answers in Slack; no persistent report artifact.
- Stateless single-turn or short multi-turn exchange.

### UC-4: Landscape and Documentation Q&A

> "How does Somtoday's authentication flow work?"

- Sources: `somtoday-docs` GitHub repository (MVP), with a generic adapter for future Confluence, docs sites, databases, and additional repos.
- Produces: conversational answers in Slack.
- Backed by a retrieval subsystem that indexes the corpus and retrieves relevant context (see [`06-docs-qa-subsystem.md`](./06-docs-qa-subsystem.md)).

---

## 5. Out of Scope (MVP)

| Item | Reason |
|---|---|
| Multi-environment routing (acceptance, test) | Production-only for MVP; env scope extension is a post-MVP ADR |
| Multi-team / multi-tenant Slack routing | Single Ops team channel initially |
| Alerting and proactive monitoring | Agent is reactive only in MVP |
| Web UI | Slack is the only control surface |
| Long-term metric trending over months | Single-window queries; historic correlation is manual |
| Replacing the VS Code workflow | Both systems coexist; the LangGraph system is additive |

---

## 6. System Architecture Diagram

```
┌──────────────────────────────────────────────────────────────────────┐
│  Slack Workspace (Ops team channel + DMs)                            │
│    Mention / Slash command  ──►  Confirmation messages  ◄──  Updates │
└────────────────────┬────────────────────────────────────────────────-┘
                     │ Slack Events API / Bolt
                     ▼
┌──────────────────────────────────────────────────────────────────────┐
│  Kubernetes (production cluster: somtoday)                           │
│                                                                      │
│  ┌─────────────────────────────────────────────────────────────┐    │
│  │  gerbil-agent Pod                                           │    │
│  │                                                             │    │
│  │  ┌──────────────┐   ┌─────────────────────────────────┐   │    │
│  │  │  Slack Bolt  │──►│  LangGraph Orchestrator         │   │    │
│  │  │  Handler     │   │  (approval gates, graph runs)   │   │    │
│  │  └──────────────┘   └────────────┬────────────────────┘   │    │
│  │                                  │                          │    │
│  │                     ┌────────────┼────────────────────┐   │    │
│  │                     ▼            ▼                    ▼   │    │
│  │              ┌────────────┐ ┌──────────┐ ┌─────────────┐ │    │
│  │              │ Grafana    │ │SmartBear │ │ Docs RAG    │ │    │
│  │              │ MCP sidecar│ │MCP sidecar│ │ subsystem   │ │    │
│  │              │ (HTTP/SSE) │ │ (stdio)  │ │ (in-process)│ │    │
│  │              └────────────┘ └──────────┘ └─────────────┘ │    │
│  │                                                             │    │
│  │  ┌──────────────────────────────────────────────────────┐  │    │
│  │  │  State store (PostgreSQL checkpointer)               │  │    │
│  │  └──────────────────────────────────────────────────────┘  │    │
│  └─────────────────────────────────────────────────────────────┘    │
│                                                                      │
│  ┌───────────────────┐                                               │
│  │  GitHub MCP       │  (HTTP/SSE — separate Deployment)            │
│  │  (mcp-server-github│                                              │
│  │  Node.js)         │                                               │
│  └───────────────────┘                                               │
│                                                                      │
│  ┌───────────────────┐                                               │
│  │  rapports PVC     │  (ReadWriteOnce, Git push job)                │
│  └───────────────────┘                                               │
└──────────────────────────────────────────────────────────────────────┘
         │                    │                    │
         ▼                    ▼                    ▼
  Grafana (prod)       Bugsnag API           GitHub API
  Prometheus           SmartBear             topicusonderwijs/iridium
                                             topicusonderwijs/somtoday-docs
```

---

## 7. Key Design Decisions

| Decision | Choice | Rationale |
|---|---|---|
| MCP transport | Hybrid (HTTP/SSE where supported, stdio sidecar otherwise) | Grafana MCP natively supports `-t sse`; SmartBear npx is stdio-only |
| LLM provider | Provider-agnostic (abstracted behind LangChain `BaseChatModel`) | Avoids lock-in; allows Azure OpenAI, Anthropic, or OpenAI swap without graph changes |
| Slack approval | Clarification loop → plan approval → per-tool-call approval (session-wide delegation available) | Maximum human control; compliant for regulated education data |
| Artifact storage | Hybrid: Git (`rapports/`) + Slack (summaries + links) | Preserves audit trail and existing workflow discipline |
| Docs Q&A corpus | MVP: `topicusonderwijs/somtoday-docs` repo; generic adapter for future sources | Simple, low-ops start; adapter contract future-proofs Confluence/DB/docs-site expansion |
| Deployment scope | Production-only MVP | Acceptance/test routing is a post-MVP concern |
| VS Code coexistence | Both systems coexist | The LangGraph system is additive, not a migration |

Full ADRs for each decision: [`09-adr/`](./09-adr/).

---

## 8. Document Map

| Document | Contents |
|---|---|
| `00-overview.md` (this file) | Scope, use cases, system diagram, key decisions |
| [`01-graph-design.md`](./01-graph-design.md) | LangGraph node/edge map per use case |
| [`02-mcp-integration.md`](./02-mcp-integration.md) | MCP transport per server, credential model |
| [`03-slack-interface.md`](./03-slack-interface.md) | Slack interaction patterns, approval policy |
| [`04-state-and-memory.md`](./04-state-and-memory.md) | State schema, checkpointer, auditability |
| [`05-output-strategy.md`](./05-output-strategy.md) | Git + Slack hybrid artifact strategy |
| [`06-docs-qa-subsystem.md`](./06-docs-qa-subsystem.md) | Retrieval system, adapter contract, MVP source |
| [`07-kubernetes.md`](./07-kubernetes.md) | K8s production topology and resource model |
| [`08-security.md`](./08-security.md) | Secrets, RBAC, network policies, data handling |
| [`09-adr/`](./09-adr/) | Architecture Decision Records |
| [`10-user-stories.md`](./10-user-stories.md) | Epics, user stories, acceptance criteria |

---

## 9. Success Criteria (MVP)

| Criterion | Measure |
|---|---|
| Release report generation | Operator triggers from Slack; full report committed to Git within 15 minutes |
| Incident investigation | Agent surfaces root cause candidates across ≥ 2 domains within 10 minutes |
| Code Q&A | Answers GitHub questions with cited commits/PRs in < 60 seconds |
| Docs Q&A | Retrieves correct answers from somtoday-docs with source citations |
| Approval coverage | 100% of MCP tool calls presented for approval before execution |
| Audit log | Every run produces a structured event log (who, what, when, approval status) |
| Uptime | Agent pod restarts without losing in-flight graph state |
