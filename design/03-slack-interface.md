# Slack Interface Design

**Version:** 0.1 (Design)  
**Date:** 2026-02-26  
**Status:** Draft

---

## 1. Overview

Slack is the **only control surface** for the Gerbil AI Suite in the Kubernetes deployment. All interactions — request submission, clarification, approval, progress updates, and artifact delivery — happen within Slack threads.

The Slack application is built with the **Bolt for Python** framework, running in Socket Mode (no public HTTP endpoint required inside the cluster).

---

## 2. Interaction Entry Points

| Entry point | Trigger | Behaviour |
|---|---|---|
| App mention | `@gerbil <request>` | Primary interaction method; starts a new run |
| Slash command | `/gerbil <request>` | Alternative entry point; identical behaviour |
| DM to @gerbil | Direct message | Same as mention; creates a private thread |
| Button callback | Interactive message button | Approval/rejection of plan or tool call |
| `resume` mention | `@gerbil resume <run_id>` | Resume a suspended or interrupted run |

---

## 3. Conversation Model

Every run is scoped to a **Slack thread**. The bot creates a reply in the thread for each interaction step so the full dialog is visible and auditable.

### 3.1 Thread lifecycle

```
User:   @gerbil generate a release report for 16.7

Bot:    🤔 Clarifying — I need a few details before I can start:
        1. What was the exact production deployment date and time? (CET)
        2. Was there a platform change (e.g. JEE8 → JEE10)?
        3. Were there any rollbacks?

User:   Deployed 2026-02-25 at 14:00 CET, JEE10, no rollbacks.

Bot:    ✅ Here is my plan for Release Report 16.7:
        Phase 0 — Deployment timeline confirmation (Slack only)
        Phase 1 — GitHub context: tags + commits in topicusonderwijs/iridium
        Phase 2 — Kubernetes pod health + rollout status
        Phase 3 — Database: PgBouncer connections, Postgres metrics
        Phase 4 — Cloudflare tunnel health
        Phase 5 — Traefik ingress metrics (dashboard rCn92aUGp)
        Phase 6 — Application metrics: response times, throughput (Wildfly)
        Phase 7 — Bugsnag: stability scores + new errors (all 3 Somtoday projects)
        Phase 8 — Synthesise to summary.md

        Estimated: 12 tool calls (~40k tokens)

        [Approve Plan] [Reject] [Modify]

User:   [clicks Approve Plan]

Bot:    ▶️ Starting Phase 1 — GitHub context...

Bot:    🔧 Tool call request:
        Server: github
        Tool:   list_releases
        Args:   { "owner": "topicusonderwijs", "repo": "iridium", "per_page": 5 }

        [Approve] [Approve all remaining] [Skip this call] [Abort run]

User:   [clicks Approve all remaining]

Bot:    ✅ Session-wide consent granted. Executing all remaining tool calls automatically.

Bot:    📋 Phase 1 complete — found releases 16.7.0 and 16.6.2.
        ...
        [phases continue silently with progress updates]
        ...

Bot:    📄 Summary ready → [View on GitHub](https://github.com/...)
        Commit: abc1234 → rapports/release_2026-02-25_16.7/summary.md

        [Excerpt of summary posted in thread]
```

---

## 4. Approval Protocol

### 4.1 Approval levels

| Level | What is asked | When triggered |
|---|---|---|
| **Clarification** | Missing or ambiguous input fields | `classify_intent` returns UNKNOWN or underspecified |
| **Plan approval** | Full execution plan (phases + tools + token estimate) | After `build_plan`, before any tool calls |
| **Tool-call approval** | Single tool call details (server, tool name, args, estimated tokens) | Before every MCP tool call, unless session consent is active |
| **Token-intensive approval** | Extra confirmation for calls estimated > 5k tokens | Flagged subset of tool-call approvals |
| **Commit approval** | Final artifact before Git push | After `synthesise`, before `commit_and_push` |

### 4.2 Session-wide consent

When the operator clicks **"Approve all remaining"** at any tool-call approval step:
- `session_consent = True` is written to graph state.
- All subsequent tool calls in the current run are executed without individual prompts.
- Consent is scoped to the run (= Slack thread); it does not persist across runs.
- A banner is posted: _"✅ Session-wide consent active for this run. All remaining tool calls will execute automatically."_

Consent can be revoked with `@gerbil pause` at any time.

### 4.3 Approval message format

```
🔧 Tool call request
─────────────────────────────
Server:  grafana
Tool:    query_metrics
Args:
  datasource_uid: PBFA97CFB590B2093
  expr: sum(pgbouncer_pools_client_active_connections{database="productie"})
  time_range: 2026-02-25T13:00:00Z → 2026-02-25T16:00:00Z
Est. tokens: ~800

[Approve]  [Approve all remaining]  [Skip this call]  [Abort run]
```

### 4.4 Token-intensive action marker

Calls estimated above 5k tokens receive an additional `⚠️ Token-intensive` prefix and a cost estimate line:

```
⚠️ Token-intensive tool call
─────────────────────────────
Server:  github
Tool:    get_pull_requests (bulk)
Args:    { "state": "closed", "since": "2026-01-01", ... }
Est. tokens: ~12,000   Est. cost: ~$0.18

[Approve]  [Approve all remaining]  [Skip this call]  [Abort run]
```

---

## 5. Progress Notifications

The bot posts progress updates at key points without requiring user action:

| Event | Message |
|---|---|
| Phase started | `▶️ Phase N — [description]...` |
| Research file written | `📋 Phase N complete — [key finding]. Saved to research/[file].md` |
| Phase skipped (no data) | `⚠️ Phase N — Data unavailable from [Source]. Continuing.` |
| Tool call skipped by user | `⏭️ Skipped: [tool name]. Phase N continues with partial data.` |
| Run paused | `⏸️ Run paused. Resume with @gerbil resume [run_id]` |
| Run cancelled | `🚫 Run cancelled.` |
| Summary ready | `📄 Summary ready — see <URL|commitment>` |

---

## 6. Commands

| Command | Description |
|---|---|
| `@gerbil <request>` | Start a new run |
| `@gerbil resume <run_id>` | Resume a paused or interrupted run |
| `@gerbil pause` | Pause the current run in this thread (suspends after current node) |
| `@gerbil status` | Show status of all active runs for the team channel |
| `@gerbil help` | List available commands and use cases |

---

## 7. Bolt App Architecture

```
SlackBoltApp (Socket Mode)
│
├── event("app_mention")        ──► intake_graph.ainvoke(slack_event)
├── event("message")            ──► clarification_reply_handler  (if thread is awaiting input)
├── action("approve_plan")      ──► resume_graph(approval=APPROVED)
├── action("reject_plan")       ──► resume_graph(approval=REJECTED)
├── action("approve_tool")      ──► resume_graph(tool_decision=APPROVED)
├── action("approve_all")       ──► resume_graph(tool_decision=APPROVE_ALL)
├── action("skip_tool")         ──► resume_graph(tool_decision=SKIP)
├── action("abort_run")         ──► resume_graph(tool_decision=ABORT)
└── action("approve_commit")    ──► resume_graph(commit_decision=APPROVED)
```

### 7.1 Thread-to-run mapping

The `slack_thread_ts` (Slack thread timestamp) is used as the LangGraph **thread ID**. This means:
- Each Slack thread maps to exactly one active LangGraph run.
- Starting a new mention in an existing thread continues the same run context (useful for follow-up questions).
- Starting a fresh mention in a new thread creates a new run.

### 7.2 Interactive message block IDs

All interactive message blocks include a `run_id` in their `action_id` or `value` field so that callbacks can route back to the correct graph run:

```json
{
  "type": "button",
  "action_id": "approve_tool",
  "value": "{\"run_id\": \"abc-123\", \"tool_call_id\": \"tc-007\"}"
}
```

---

## 8. Error Messages to the Operator

| Situation | Slack message |
|---|---|
| MCP server unreachable | `❌ [Server] MCP server is unreachable. Phase [N] skipped. Run [run_id] continued with data gap.` |
| LLM rate limit | `⏳ Rate limit hit. Retrying in [N]s... (attempt 2/3)` |
| Git push failed | `⚠️ Git push failed. Summary attached as file. Manual commit required.` |
| Unknown intent after 3 clarification rounds | `❓ I'm unable to determine the intent after 3 rounds of clarification. Please rephrase or use /gerbil help.` |
| Pod restart recovery | `🔄 Run [run_id] recovered after pod restart. Resuming from phase [N].` |

---

## 9. Rate Limiting and Concurrency

- Maximum **2 concurrent runs per channel** to prevent flooding.
- If a third run is requested: the bot queues it and notifies the user with estimated wait time.
- Rate limit on Slack messages: max 1 message per second per channel (Bolt handles this natively).
- Token-intensive runs queue behind ongoing token-intensive runs (singleton guard on `session_consent = True` runs).
