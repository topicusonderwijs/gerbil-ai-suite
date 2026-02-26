# State and Memory Design

**Version:** 0.1 (Design)  
**Date:** 2026-02-26  
**Status:** Draft

---

## 1. Overview

This document defines how LangGraph state is structured, persisted, and retrieved across the lifecycle of a run. It also addresses cross-run memory (conversation history, approval history, run index) and the compliance requirements for an operations system handling production data from a regulated school platform.

---

## 2. State Hierarchy

```
GerbilBaseState               (shared by all graphs)
 ├── ReleaseState              (UC-1: Release Report)
 ├── IncidentState             (UC-2: Incident Postmortem)
 ├── CodeQAState               (UC-3: Code Q&A)
 └── DocsQAState               (UC-4: Docs Q&A)
```

---

## 3. Base State Schema

```python
from typing import Annotated, TypedDict
from langgraph.graph.message import add_messages

class ApprovalRecord(TypedDict):
    tool_call_id: str
    server: str
    tool_name: str
    args: dict
    decision: str           # APPROVED | SKIPPED | APPROVE_ALL | ABORTED
    timestamp: str          # ISO8601 UTC
    user_id: str            # Slack user who made the decision
    estimated_tokens: int

class DeploymentTimeline(TypedDict):
    code_version: str
    deployment_datetime: str    # ISO8601 UTC (confirmed by operator)
    platform: str               # e.g. "JEE10"
    rollbacks: list[dict]       # [{rolled_back_at, redeployed_at, platform}]
    confirmed_by: str           # Slack user_id

class GerbilBaseState(TypedDict):
    # ── Run identity ────────────────────────────────────────────────────
    run_id: str                         # LangGraph run ID (UUID)
    slack_thread_ts: str                # Slack thread timestamp (= LangGraph thread_id)
    slack_channel: str
    slack_team_id: str
    user_id: str                        # Slack user who triggered the run
    created_at: str                     # ISO8601 UTC

    # ── Intent and entities ─────────────────────────────────────────────
    intent: str                         # RELEASE | INCIDENT | CODE_QA | DOCS_QA
    raw_request: str                    # Original user text
    entities: dict                      # Extracted: version, time_window, component, ...

    # ── Approval ────────────────────────────────────────────────────────
    session_consent: bool               # True = skip per-call approval for this run
    approval_log: list[ApprovalRecord]

    # ── Execution progress ──────────────────────────────────────────────
    current_phase: str
    completed_phases: list[str]
    data_gaps: list[str]                # Phases/tools that returned no data

    # ── Artifacts ───────────────────────────────────────────────────────
    artifact_dir: str                   # Path on PVC, e.g. rapports/release_2026-02-25_16.7/
    research_files: dict[str, str]      # {domain: abs_path_on_pvc}
    git_commit_sha: str | None
    final_summary_path: str | None

    # ── LLM message history ─────────────────────────────────────────────
    messages: Annotated[list, add_messages]
```

---

## 4. Use-Case State Extensions

```python
class ReleaseState(GerbilBaseState):
    release_version: str
    previous_version: str
    deployment_timeline: DeploymentTimeline
    github_changelog: list[dict]        # commits/PRs between versions

class IncidentState(GerbilBaseState):
    incident_title: str
    time_window_start: str              # ISO8601 UTC
    time_window_end: str                # ISO8601 UTC
    affected_components: list[str]
    hypotheses: list[str]               # User-provided
    hypothesis_results: dict            # {hypothesis: CONFIRMED|PROBABLE|UNCERTAIN|REFUTED}
    deployment_timeline: DeploymentTimeline

class CodeQAState(GerbilBaseState):
    question: str
    target_repo: str                    # default: topicusonderwijs/iridium
    cited_refs: list[str]               # commit SHAs, PR numbers referenced in answer

class DocsQAState(GerbilBaseState):
    question: str
    retrieved_chunks: list[dict]        # {source, content, score}
    answer: str
```

---

## 5. Persistence: PostgreSQL Checkpointer

### 5.1 Checkpointer choice

**LangGraph `PostgresSaver`** (from `langgraph-checkpoint-postgres`).

Rationale:
- Native LangGraph integration; no custom serialization needed.
- Enables `interrupt()` / human-in-the-loop suspension without a separate queue.
- Enables `resume` from any node on pod restart.
- Postgres is a standard K8s workload; reliable, back-up friendly.

### 5.2 Database schema (managed by LangGraph)

LangGraph creates and manages two tables:
- `checkpoints` — serialized state snapshots per thread + checkpoint ID.
- `checkpoint_writes` — pending writes (for exactly-once semantics).

The application creates one additional table for the run index:

```sql
CREATE TABLE gerbil_runs (
    run_id          UUID PRIMARY KEY,
    slack_thread_ts TEXT NOT NULL,
    slack_channel   TEXT NOT NULL,
    slack_team_id   TEXT NOT NULL,
    user_id         TEXT NOT NULL,
    intent          TEXT NOT NULL,
    status          TEXT NOT NULL,  -- RUNNING | COMPLETED | CANCELLED | FAILED
    created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
    completed_at    TIMESTAMPTZ,
    artifact_dir    TEXT,
    git_commit_sha  TEXT
);
```

This index is used by `@gerbil status` and by the audit log query interface.

### 5.3 PostgreSQL deployment

| Parameter | Value |
|---|---|
| Image | `postgres:16-alpine` |
| Database name | `gerbil` |
| Storage | 10 GiB PVC (ReadWriteOnce) |
| Namespace | `gerbil` |
| Connection | `POSTGRES_URL` environment variable in `gerbil-agent` |

---

## 6. State Lifecycle

```
[run created]          → state written to checkpoint with status=RUNNING
[node completed]       → checkpoint updated (partial state persisted)
[interrupt() hit]      → state frozen; bot posts Slack message; pod may be recycled
[user responds]        → Bolt handler calls graph.ainvoke(resume=...) with thread_id
[graph completed]      → final checkpoint; gerbil_runs.status = COMPLETED
[run cancelled]        → gerbil_runs.status = CANCELLED; checkpoint retained for 30 days
[pod restart]          → on startup, bot checks for RUNNING runs; auto-resumes from last checkpoint
```

---

## 7. Cross-Session Memory

The MVP does **not** implement cross-session semantic memory (no vector store of past conversations). This is a future capability.

What is available cross-session:

| Data | Persistence | Use |
|---|---|---|
| `gerbil_runs` index | Postgres | `@gerbil status`, audit queries |
| Approval log (per run) | Postgres (embedded in checkpoint) | Compliance audit |
| Generated artifacts | Git + PVC | Historical context readable by humans |
| Checkpoints (30-day TTL) | Postgres | Resume interrupted runs |

### 7.1 Future: cross-session context

Design for future reference only (not MVP):
- Vector store of past `summary.md` and `research/*.md` artifacts.
- Query: "compare to last week's release report".
- Implementation: `pgvector` extension on the same Postgres instance, nightly ingestion job.

---

## 8. Message History Management

LangGraph accumulates `messages` in state. For long-running research workflows (8 phases × multiple tool calls), this can grow large. Strategy:

1. **Summarisation at phase boundaries:** After each phase, the LLM produces a one-paragraph summary of the phase output. The raw tool call results are stored in the research file (persistent artifact); only the summary is kept in `messages`.
2. **Hard cap:** Maximum 50 messages in `messages`; oldest messages are summarised and compacted when the cap is reached.
3. **Research files as the source of truth:** The `messages` list is for LLM context window; the research files are the durable record.

---

## 9. Audit Log Requirements

Every run must produce a structured audit log entry accessible to the team. The `approval_log` field satisfies this requirement:

```json
{
  "run_id": "abc-123",
  "slack_thread_ts": "1740000000.001234",
  "user_id": "U0123456",
  "intent": "RELEASE",
  "approval_log": [
    {
      "tool_call_id": "tc-001",
      "server": "github",
      "tool_name": "list_releases",
      "args": {"owner": "topicusonderwijs", "repo": "iridium"},
      "decision": "APPROVED",
      "timestamp": "2026-02-25T13:15:00Z",
      "user_id": "U0123456",
      "estimated_tokens": 400
    },
    {
      "tool_call_id": "tc-002",
      "server": "grafana",
      "tool_name": "query_metrics",
      "args": {"expr": "..."},
      "decision": "APPROVE_ALL",
      "timestamp": "2026-02-25T13:15:45Z",
      "user_id": "U0123456",
      "estimated_tokens": 900
    }
  ]
}
```

Audit logs are queryable via Postgres (`gerbil_runs` + checkpoint `approval_log` field). A future reporting endpoint could expose these as a JSON API.

---

## 10. Data Retention

| Data | Retention | Justification |
|---|---|---|
| Active run checkpoints | Until run completion + 30 days | Enable debugging of recent failures |
| Completed run checkpoints | 30 days | Short-term audit trail |
| `gerbil_runs` index rows | 1 year | Operational statistics |
| Generated artifacts (Git) | Permanent | Version-controlled audit trail |
| Slack messages | Governed by Slack workspace policy | Not controlled by this system |
