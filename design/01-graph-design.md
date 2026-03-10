# LangGraph Design

**Version:** 0.1 (Design)  
**Date:** 2026-02-26  
**Status:** Draft

---

## 1. Overview

Each use case maps to a dedicated LangGraph `StateGraph`. All graphs share a common **entry/exit wrapper** that handles:

- Slack event deserialization and run scoping
- The clarification loop (ask → refine until clear)
- The plan-approval gate (present plan → wait for Slack approval)
- Per-tool-call approval (send tool description → wait → execute or abort)
- Final output routing (Git commit + Slack summary)

The shared wrapper is implemented as a composable sub-graph (`intake_graph`) that feeds into the use-case-specific graphs.

---

## 2. Shared: Intake Graph

```
[slack_event]
     │
     ▼
[parse_request]                 ← extract intent, entities, time window
     │
     ▼
[classify_intent]               ← route to: RELEASE | INCIDENT | CODE_QA | DOCS_QA | UNKNOWN
     │
     ├── UNKNOWN ──────────────► [ask_clarification]
     │                                 │ (Slack message → wait for reply)
     │                           [clarification_received]
     │                                 │
     │                           [classify_intent]   (loop back)
     │
     ▼ (known intent)
[build_plan]                    ← enumerate phases, tools, estimated token cost
     │
     ▼
[present_plan_for_approval]     ← Slack interactive message with Approve / Reject / Modify
     │
     ├── Reject ────────────────► [END: cancelled]
     ├── Modify ────────────────► [ask_clarification]  (loop back)
     │
     ▼ Approve
[route_to_graph]                ← hand off to use-case graph
```

### Node responsibilities

| Node | Inputs | Outputs | Notes |
|---|---|---|---|
| `parse_request` | Slack event payload | `intent_hint`, `entities`, `raw_text` | Structured extraction via LLM |
| `classify_intent` | `raw_text`, `entities` | `intent: Enum` | `RELEASE \| INCIDENT \| CODE_QA \| DOCS_QA \| UNKNOWN` |
| `ask_clarification` | `missing_fields: list[str]` | `clarification_message` | Posts to Slack thread; suspends |
| `build_plan` | `intent`, `entities` | `plan: Plan` | Enumerates phases + tools + token estimate |
| `present_plan_for_approval` | `plan` | `approval_status` | Interactive Slack block; suspends |
| `route_to_graph` | `intent`, `approved_plan` | — | Spawns child graph run |

---

## 3. UC-1 / UC-2: Research Graphs (Incident + Release)

The two research workflows share the same graph skeleton — only the phase node set and output template differ.

### 3.1 Graph skeleton

```
[setup_run]                     ← create rapports/DIR/research/, initialise state
     │
     ▼
[verify_deployment_timeline]    ← MANDATORY for both UC-1 and UC-2: ask user for exact deploy time, rollbacks, platform
     │  (Slack prompt → wait for confirmation)
     ▼
[phase_node_1]  ──[tool_call_approved?]──► execute ──► write_research_file
     │
     ▼
[phase_node_2]  ──[tool_call_approved?]──► execute ──► write_research_file
     │
     ▼
    ...
     │
     ▼
[phase_node_N]
     │
     ▼
[synthesise]                    ← read all research files, build summary.md
     │
     ▼
[present_summary_for_approval]  ← Slack: "Here is the summary — Commit to Git / Discard?"
     │
     ▼ Approved
[commit_and_push]               ← git add + commit + push rapports/ dir
     │
     ▼
[notify_slack]                  ← post summary excerpt + link to Git diff
     │
     ▼
[END]
```

### 3.2 Per-tool-call approval node

Every tool call is wrapped by an approval gate. Operators can grant **session-wide consent** to skip individual gates for the remainder of the run.

```
[prepare_tool_call]
     │
     ├── session_consent_granted? ──► [execute_tool]
     │
     ▼ (no session consent)
[request_tool_approval]         ← Slack message: tool name, description, args preview, token estimate
     │
     ├── Reject ────────────────► [tool_skipped] ──► [phase_node continues with partial data]
     ├── Approve All ───────────► [set session_consent = true] ──► [execute_tool]
     │
     ▼ Approve (single)
[execute_tool]
     │
     ▼
[handle_tool_result]
```

### 3.3 Release Report phases

Derived from [`release_rapport.agent.md`](../.github/agents/release_rapport.agent.md):

| Node | Phase | MCP tools | Research file |
|---|---|---|---|
| `verify_deployment_timeline` | Phase 0 | — (Slack only) | header of all files |
| `gather_github_context` | Phase 1 | `github/releases`, `github/commits` | — |
| `research_kubernetes` | Phase 2 | `grafana/query`, `grafana/dashboard` | `research/kubernetes.md` |
| `research_database` | Phase 3 | `grafana/query` (PgBouncer, Postgres) | `research/database.md` |
| `research_cloudflare` | Phase 4 | `grafana/query` (Cloudflared dashboard `2WhbDNm7z`) | `research/cloudflare.md` |
| `research_proxy` | Phase 5 | `grafana/query` (Traefik dashboard `rCn92aUGp`) | `research/proxy.md` |
| `research_application` | Phase 6 | `grafana/query` (Wildfly datasource `RU1hwHA4k`) | `research/application.md` |
| `research_exceptions` | Phase 7 | `smartbear/errors`, `smartbear/stability` | `research/exceptions.md` |
| `synthesise` | Phase 8 | — | `summary.md` |

### 3.4 Incident Postmortem phases

Derived from [`incident_analysis.agent.md`](../.github/agents/incident_analysis.agent.md):

| Node | Phase | MCP tools | Research file |
|---|---|---|---|
| `parse_incident` | Phase 0 | — (Slack only) | header of all files |
| `verify_deployment_timeline` | Phase 0b | — (Slack only) | header of all files |
| `gather_github_context` | Phase 1 | `github/commits`, `github/compare` | — |
| `research_database` | Phase 2 | `grafana/query` (PgBouncer + Postgres dashboards) | `research/database.md` |
| `research_kubernetes` | Phase 3 | `grafana/query`, `grafana/dashboard` | `research/kubernetes.md` |
| `research_cloudflare` | Phase 4 | `grafana/query` (dashboard `2WhbDNm7z`) | `research/cloudflare.md` |
| `research_proxy` | Phase 5 | `grafana/query` (dashboard `rCn92aUGp`) | `research/proxy.md` |
| `research_application` | Phase 6 | `grafana/query` (Wildfly + Traefik) | `research/application.md` |
| `research_exceptions` | Phase 7 | `smartbear/errors`, `github/commits` | `research/exceptions.md` |
| `synthesise` | Phase 8 | — | `summary.md` |

> **Note:** Phase 1 (`gather_github_context`) is included in the incident workflow to identify recent deployments and code changes that may correlate with the incident timeline. This is essential for hypothesis validation in Phase 8.

---

## 4. UC-3: Code Q&A Graph

Short-lived, conversational. No persistent artifact.

```
[parse_code_question]
     │
     ▼
[plan_github_queries]           ← enumerate: repo search, diff, PR list, file read
     │
     ▼
[approve_github_queries]        ← Slack approval (or session consent)
     │
     ▼
[execute_github_queries]        ← github/* MCP tools
     │
     ▼
[synthesise_answer]             ← cited answer referencing commit SHAs / PR numbers
     │
     ▼
[post_to_slack]
     │
     ▼
[END]
```

### Tool set

| Tool | Purpose |
|---|---|
| `github/search_code` | Find symbols or patterns across `iridium` |
| `github/get_commits` | List commits in a date range or branch |
| `github/compare` | Diff two tags or branches |
| `github/get_pull_request` | Read PR description + review comments |
| `github/list_issues` | Find linked issues |

---

## 5. UC-4: Docs Q&A Graph

Short-lived. Backed by the retrieval subsystem (see [`06-docs-qa-subsystem.md`](./06-docs-qa-subsystem.md)).

```
[parse_docs_question]
     │
     ▼
[retrieve_context]              ← RAG: embed query → vector search → fetch chunks
     │
     ▼
[synthesise_answer]             ← grounded answer with source citations
     │
     ▼
[post_to_slack]
     │
     ▼
[END]
```

No MCP tool calls are made; the retrieval subsystem handles corpus access internally. No approval gate is needed for MCP calls since there are none.

> **Note on LLM calls:** The embedding query and answer synthesis steps do invoke the LLM provider (external API call), but these are exempt from the per-call approval model because they are (a) inherent to every LangGraph node and cannot be individually gated, (b) read-only with respect to external systems, and (c) covered by the initial plan approval. This is consistent with UC-3 (Code Q&A), where LLM synthesis calls are also not individually approved.

---

## 6. State Schema

All graphs operate on a shared base state, extended per use case. The **canonical state schema** is defined in [`04-state-and-memory.md`](./04-state-and-memory.md). A summary is shown here for convenience; in case of discrepancy, `04-state-and-memory.md` is authoritative.

```python
class GerbilBaseState(TypedDict):
    # Identity
    slack_thread_ts: str          # Slack thread timestamp (run scope key)
    slack_channel: str
    slack_team_id: str
    run_id: str                   # LangGraph run ID
    user_id: str                  # Slack user who triggered
    created_at: str               # ISO8601 UTC

    # Intent
    intent: str                   # RELEASE | INCIDENT | CODE_QA | DOCS_QA
    raw_request: str              # Original user text
    entities: dict                # extracted: version, time_window, component, ...

    # Approval
    session_consent: bool         # True = operator approved all remaining tool calls
    approval_log: list[dict]      # {tool, args, decision, timestamp, user_id}

    # Progress
    current_phase: str
    completed_phases: list[str]
    data_gaps: list[str]          # Phases/tools that returned no data
    research_files: dict          # {filename: path_on_pvc}

    # Output
    artifact_dir: str             # rapports/DIR/ on PVC
    git_commit_sha: str | None
    final_summary_path: str | None

    # Messages (LangGraph messages list for LLM context)
    messages: Annotated[list, add_messages]
```

```python
class ReleaseState(GerbilBaseState):
    release_version: str
    previous_version: str
    deployment_timeline: dict     # confirmed by user in Phase 0

class IncidentState(GerbilBaseState):
    incident_title: str
    time_window_start: str        # ISO8601 UTC
    time_window_end: str
    affected_components: list[str]
    hypotheses: list[str]
    deployment_timeline: dict
```

---

## 7. Checkpointing and Resumability

- LangGraph `PostgresSaver` checkpointer persists state after every node.
- If the pod restarts mid-run, the operator can resume with `@gerbil resume <run_id>`.
- Suspension points (approval wait, clarification wait) are implemented as `interrupt()` nodes in LangGraph's human-in-the-loop API.
- Thread ID = `slack_thread_ts` so a run is always scoped to its originating Slack thread.

---

## 8. Error Handling

| Failure type | Handling |
|---|---|
| MCP tool returns error | Log to research file as "Data unavailable from [Source]"; continue phase |
| MCP server unreachable | Notify Slack, skip phase, mark as DATA_GAP in summary |
| LLM rate limit | Exponential backoff, max 3 retries |
| Operator rejects entire run | `END: cancelled`, no artifact written |
| Pod restart | Resume from last checkpoint on restart |
| Git push conflict | Retry with rebase; if still failing, upload file to Slack as fallback |
