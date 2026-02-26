# User Stories and Epics

**Version:** 0.1 (Design)  
**Date:** 2026-02-26  
**Status:** Draft

---

## Overview

Stories are organized into **Epics** aligned with the design documents. Implementation order follows a dependency-first sequence: infrastructure before integrations, integrations before workflows, workflows before advanced features.

**Recommended rollout order:**

```
Epic 1: Foundation          ← K8s namespace, secrets, Postgres, PVC
Epic 2: MCP Integration     ← Grafana, GitHub, SmartBear clients
Epic 3: Slack Bot           ← Bolt app, approval model, command routing
Epic 4: LangGraph Core      ← Intake graph, state schema, checkpointer
Epic 5: Release Reports     ← UC-2 workflow, Git push, Slack delivery
Epic 6: Incident Analysis   ← UC-1 workflow
Epic 7: Code Q&A            ← UC-3 workflow
Epic 8: Docs Q&A            ← UC-4 subsystem, ingestion pipeline
Epic 9: Hardening           ← health checks, scaling, security audit
```

---

## Epic 1: Foundation

> Set up the Kubernetes namespace, persistent storage, secrets scaffolding, and Postgres for LangGraph state.

---

### US-1.1 — Kubernetes namespace and base configuration

**As** an ops engineer  
**I want** a dedicated `gerbil` namespace with base RBAC and network policies  
**So that** all Gerbil components are isolated from other workloads

**Acceptance criteria:**
- [ ] `gerbil` namespace exists in the `somtoday` production cluster
- [ ] Default deny-all ingress NetworkPolicy applied to namespace
- [ ] `gerbil-agent-sa` ServiceAccount created with no cluster-level permissions
- [ ] Egress policy allows agent pod to reach external HTTPS (443) and internal services

**Technical tasks:**
- Create namespace manifest
- Apply NetworkPolicy manifests (see [`07-kubernetes.md §5`](./07-kubernetes.md))
- Create ServiceAccount manifest

---

### US-1.2 — Kubernetes Secrets scaffold

**As** an ops engineer  
**I want** all required Kubernetes Secrets created from a documented runbook  
**So that** no secrets are stored in Git and all pods can access credentials at startup

**Acceptance criteria:**
- [ ] All 7 secrets defined in [`08-security.md §3`](./08-security.md) are created in `gerbil` namespace
- [ ] All secret values are sourced from Vault / 1Password / equivalent (not from `.env` file directly)
- [ ] Runbook document exists describing how to rotate each secret
- [ ] No secret key appears in any ConfigMap, Deployment env-value, or Git commit

**Technical tasks:**
- Write secrets creation runbook (not committed; stored in secure docs)
- Create secret rotation reminder calendar entries (per rotation schedule in §3.2)

---

### US-1.3 — Postgres StatefulSet

**As** the LangGraph orchestrator  
**I want** a Postgres 16 instance in the `gerbil` namespace  
**So that** run checkpoints, the run index, and future vector embeddings can be persisted

**Acceptance criteria:**
- [ ] `gerbil-postgres` StatefulSet deployed with 10 GiB PVC
- [ ] Database `gerbil` created on startup
- [ ] `pgvector` extension installed (needed for future docs Q&A)
- [ ] Connection string available via `postgres-secret`
- [ ] Daily backup job configured (PVC snapshot or pg_dump CronJob)

**Technical tasks:**
- Write StatefulSet manifest with init SQL script
- Write postgres-svc ClusterIP Service manifest
- Write backup CronJob manifest (output to PVC or object storage)

---

### US-1.4 — Rapports PVC and Git init container

**As** the report generation workflow  
**I want** the `rapports/` Git repository cloned and available as a PVC mount at pod startup  
**So that** phase nodes can write research files directly to the filesystem

**Acceptance criteria:**
- [ ] 5 GiB ReadWriteOnce PVC `rapports-pvc` provisioned in `gerbil` namespace
- [ ] `git-init` InitContainer clones repository from `GIT_REPO_URL` on first start
- [ ] On subsequent starts, InitContainer performs `git pull --rebase`
- [ ] Main container has read-write access to `/rapports` mount
- [ ] SSH deploy key (restricted to this repo) used for clone/push

**Technical tasks:**
- Write PVC manifest
- Write InitContainer spec
- Create deploy key in GitHub and store as `gitpush-secret`

---

## Epic 2: MCP Integration

> Implement and verify the three MCP client connections from the LangGraph app.

---

### US-2.1 — Grafana MCP service (HTTP/SSE)

**As** the LangGraph orchestrator  
**I want** a running Grafana MCP server accessible at `http://grafana-mcp-svc:8080/sse`  
**So that** graph nodes can query Grafana metrics and dashboards

**Acceptance criteria:**
- [ ] `grafana-mcp` Deployment running with `mcp/grafana` image and `-t sse` flag
- [ ] ClusterIP Service `grafana-mcp-svc` exposes port 8080
- [ ] Python `MCPClient(transport="sse", url=...)` can list available tools successfully
- [ ] `grafana/query` and `grafana/get_dashboard_by_uid` tool calls return data for a known dashboard (e.g. `K3Q86qtGz`)
- [ ] Credentials loaded via `grafana-mcp-secret`; not visible in pod env listing outside the namespace

**Technical tasks:**
- Write Deployment and Service manifests (see [`07-kubernetes.md §4.2`](./07-kubernetes.md))
- Verify SSE port with `docker run mcp/grafana -t sse --help` in spike
- Write integration test: list tools + one test query against `PBFA97CFB590B2093` datasource

---

### US-2.2 — GitHub MCP service (HTTP/SSE)

**As** the LangGraph orchestrator  
**I want** a running GitHub MCP server accessible at `http://github-mcp-svc:3000/sse`  
**So that** graph nodes can query releases, commits, and code from `topicusonderwijs/iridium`

**Acceptance criteria:**
- [ ] `github-mcp` Deployment running with `@modelcontextprotocol/server-github` and `--transport sse`
- [ ] ClusterIP Service `github-mcp-svc` exposes port 3000
- [ ] `github/list_releases` call returns at least the last 3 releases from `topicusonderwijs/iridium`
- [ ] Fine-grained PAT scoped to `topicusonderwijs/iridium` + `topicusonderwijs/somtoday-docs` (read-only)

**Technical tasks:**
- Write Deployment and Service manifests (see [`07-kubernetes.md §4.3`](./07-kubernetes.md))
- Verify `--transport sse` flag availability in a spike
- Write integration test

---

### US-2.3 — SmartBear MCP sidecar (stdio)

**As** the LangGraph orchestrator  
**I want** the SmartBear Bugsnag MCP server available as a sidecar in the `gerbil-agent` pod  
**So that** graph nodes can query Bugsnag error rates and stability scores

**Acceptance criteria:**
- [ ] `smartbear-mcp` sidecar container running `npx -y @smartbear/mcp@latest` in `gerbil-agent` pod
- [ ] Python `MCPClient(transport="stdio", command=[...])` can list available tools
- [ ] `smartbear/list_errors` with filter `app.release_stage = "production"` returns errors for project `543ce4797765623fb900011d`
- [ ] Bugsnag auth token loaded via `smartbear-mcp-secret`

**Technical tasks:**
- Add sidecar container spec to `gerbil-agent` Deployment
- Implement stdio bridge (direct subprocess spawn from Python MCP SDK)
- Write integration test covering both `"production"` and `"productie"` release stage filter variants

---

### US-2.4 — MCP Registry and tool dispatch

**As** a LangGraph graph node  
**I want** a unified `MCPRegistry` that provides named access to all three MCP clients  
**So that** nodes can call `REGISTRY["grafana"].call_tool(...)` without knowing transport details

**Acceptance criteria:**
- [ ] `MCPRegistry` initialises all three sessions at application startup
- [ ] Health check endpoint reports per-client connection status
- [ ] Reconnect logic handles transient disconnections (max 5 attempts, exponential backoff)
- [ ] `execute_mcp_tool()` wrapper enforces approval gate before every call (see [`01-graph-design.md §3.2`](./01-graph-design.md))

**Technical tasks:**
- Implement `mcp_registry.py`
- Implement `execute_mcp_tool()` approval wrapper
- Add `/health` endpoint with MCP status to the FastAPI/Starlette health server

---

## Epic 3: Slack Bot

> Implement the Slack Bolt app with Socket Mode, approval interaction pattern, and command routing.

---

### US-3.1 — Slack Bolt app in Socket Mode

**As** an operator  
**I want** to mention `@gerbil <request>` in Slack and receive a reply in-thread  
**So that** I can initiate agent runs from our ops channel

**Acceptance criteria:**
- [ ] Bolt app starts in Socket Mode using `SLACK_APP_TOKEN`
- [ ] `app_mention` event received and logged
- [ ] Bot replies in the same thread as the mention
- [ ] DM to @gerbil also works (creates private thread)
- [ ] Bot token has minimum required scopes (see [`08-security.md §4.5`](./08-security.md))

**Technical tasks:**
- Implement `slack_app.py` with Bolt Socket Mode
- Register `app_mention` and `message` event listeners
- Implement thread reply helper

---

### US-3.2 — Intent classification and clarification loop

**As** an operator  
**I want** the bot to ask me clarifying questions when my request is ambiguous  
**So that** the agent always starts with sufficient context before executing

**Acceptance criteria:**
- [ ] Requests matching a known use case (RELEASE, INCIDENT, CODE_QA, DOCS_QA) skip the clarification step
- [ ] Ambiguous requests trigger a clarification message listing missing fields
- [ ] Operator's reply in the same thread is consumed as clarification input
- [ ] After 3 failed clarification rounds, bot posts a helpful error and stops
- [ ] Clarification replies correctly handle multi-sentence answers

**Technical tasks:**
- Implement `classify_intent` node with LLM prompt
- Implement `ask_clarification` interrupt node
- Implement `clarification_reply_handler` Bolt message listener

---

### US-3.3 — Plan approval interactive message

**As** an operator  
**I want** to see and approve the agent's execution plan before any tool calls  
**So that** I understand what will happen and can modify or reject the plan

**Acceptance criteria:**
- [ ] Plan message lists all phases, tools, and estimated total token count
- [ ] Three buttons: Approve Plan / Reject / Modify
- [ ] Approval records user_id, timestamp, and plan hash in graph state
- [ ] Rejection posts "Run cancelled" and ends the graph
- [ ] Modify routes back to the clarification loop with the plan visible

**Technical tasks:**
- Implement `build_plan` node (produce `Plan` object with phases + tools + token estimate)
- Implement `present_plan_for_approval` interrupt node with Block Kit message
- Register `approve_plan`, `reject_plan`, `modify_plan` action handlers

---

### US-3.4 — Per-tool-call approval with session consent

**As** an operator  
**I want** to approve each tool call individually, with the option to approve all at once  
**So that** I have full control but can also delegate for the duration of a run

**Acceptance criteria:**
- [ ] Every MCP tool call is presented as an approval message (server, tool, args, token estimate)
- [ ] Approve / Approve all remaining / Skip / Abort buttons function correctly
- [ ] "Approve all" sets `session_consent = True` and posts a banner
- [ ] Skipped calls are noted in research files as DATA_GAP entries
- [ ] "Abort" posts "Run aborted" and ends the graph from any point
- [ ] Token-intensive calls (>5k tokens) show `⚠️` prefix and cost estimate

**Technical tasks:**
- Implement `request_tool_approval` interrupt node
- Implement Block Kit approval message builder (with token-intensive variant)
- Register `approve_tool`, `approve_all`, `skip_tool`, `abort_run` action handlers
- Implement token estimation utility (rough: chars / 4)

---

### US-3.5 — Progress updates and phase notifications

**As** an operator  
**I want** to see progress updates as each phase completes  
**So that** I know the run is progressing and what it found

**Acceptance criteria:**
- [ ] Phase-start message posted at beginning of each phase
- [ ] Phase-complete message posted after research file is written (key finding + file path)
- [ ] DATA_GAP phases post a warning message and continue
- [ ] Messages are posted in the originating Slack thread (not as a new top-level message)

**Technical tasks:**
- Implement `post_progress(state, message)` helper
- Add progress calls to each phase node entry/exit

---

## Epic 4: LangGraph Core

> Implement the shared intake graph, base state, Postgres checkpointer, and resumability.

---

### US-4.1 — Base state schema and Postgres checkpointer

**As** the LangGraph orchestrator  
**I want** a typed `GerbilBaseState` and a `PostgresSaver` checkpointer  
**So that** all runs are persisted to Postgres and can survive pod restarts

**Acceptance criteria:**
- [ ] `GerbilBaseState` TypedDict implemented as per [`04-state-and-memory.md §3`](./04-state-and-memory.md)
- [ ] `PostgresSaver` connected to `gerbil-postgres` instance
- [ ] `gerbil_runs` index table created at startup
- [ ] After a pod restart, any RUNNING run is detected; Slack thread receives "recovering" message
- [ ] `@gerbil resume <run_id>` command manually resumes a suspended run

**Technical tasks:**
- Implement state schemas in `state.py`
- Configure `PostgresSaver` in app startup
- Implement startup recovery check (query `gerbil_runs` for RUNNING rows)
- Implement `resume` command handler

---

### US-4.2 — Intake graph (classify + clarify + plan + route)

**As** the Slack bot  
**I want** a complete intake graph that classifies intent, clarifies, plans, and routes to the correct use-case graph  
**So that** all four use cases share a consistent entry point

**Acceptance criteria:**
- [ ] `intake_graph` implemented with nodes: `parse_request`, `classify_intent`, `ask_clarification`, `build_plan`, `present_plan_for_approval`, `route_to_graph`
- [ ] Routes correctly to RELEASE, INCIDENT, CODE_QA, DOCS_QA sub-graphs
- [ ] Handles UNKNOWN intent with clarification loop
- [ ] `thread_id = slack_thread_ts` correctly scopes runs to their thread

**Technical tasks:**
- Implement `intake_graph.py` as a LangGraph `StateGraph`
- Implement `route_to_graph` node with sub-graph invocation
- Write unit tests for each intent classification case

---

## Epic 5: Release Report (UC-2)

> Implement the full 8-phase release report workflow, Git commit, and Slack delivery.

---

### US-5.1 — Deployment timeline verification (Phase 0)

**As** an operator  
**I want** the agent to ask me for the exact deployment date, platform, and rollback history before proceeding  
**So that** the report correctly attributes errors and metrics to the actual deployment window

**Acceptance criteria:**
- [ ] Agent posts specific questions about deployment time (CET + timezone), platform change, rollbackss
- [ ] Operator's answers are parsed and stored in `DeploymentTimeline` state field
- [ ] `deployment_timeline` is written as a header in every research file
- [ ] If operator skips the question, run is paused with a reminder (not auto-filled with GitHub release date)

**Technical tasks:**
- Implement `verify_deployment_timeline` interrupt node
- Implement `DeploymentTimeline` parsing from free-text answer

---

### US-5.2 — Research phase nodes (Phases 1–7)

**As** the release report workflow  
**I want** each of the 7 research phases to query the correct MCP tools and write a research file immediately  
**So that** data is durably captured as soon as it is collected

**Acceptance criteria (per phase):**
- [ ] Phase node calls correct MCP tools with correct labels/filters (see [`01-graph-design.md §3.3`](./01-graph-design.md))
- [ ] Research file is written to PVC immediately after tool calls return
- [ ] Research file follows the templates defined in [`release_rapport.agent.md`](../.github/agents/release_rapport.agent.md)
- [ ] DATA_GAP entries are written when tools return errors or empty results
- [ ] All timestamps in research files include both CET and UTC

**Phases to implement:** Phases 1–7 from [`01-graph-design.md §3.3`](./01-graph-design.md).

**Technical tasks (per phase):** Implement phase node, correct PromQL/Bugsnag filter, research file writer, approval gate integration.

**Critical filters to validate (from [`copilot-instructions.md`](../.github/copilot-instructions.md)):**
- Bugsnag Backend (`543ce4797765623fb900011d`): `app.release_stage = "production"` (not `"productie"`)
- Bugsnag Docent/Leerling: `app.release_stage = "productie"`
- Grafana production: `kubernetes_cluster="somtoday"`, `environment="productie"`
- Traefik: `k8s_cluster="somtoday"`, `k8s_namespace="traefik"`

---

### US-5.3 — Synthesis and summary generation (Phase 8)

**As** the release report workflow  
**I want** the agent to read all research files and generate a `summary.md` following the existing template  
**So that** the final report is consistent with existing reports in `rapports/`

**Acceptance criteria:**
- [ ] `synthesise` node reads all research files from PVC
- [ ] Output follows [`template/release_rapport.md`](../template/release_rapport.md) structure
- [ ] Summary includes Go/No-Go recommendation with supporting evidence
- [ ] All metric deltas (current vs previous) are calculated and shown
- [ ] Traffic normalisation warning is included if traffic differs >20% between comparison windows

**Technical tasks:**
- Implement `synthesise` node with research-files-as-context prompt
- Implement `summary.md` writer
- Validate output structure against template

---

### US-5.4 — Git commit and Slack delivery

**As** an operator  
**I want** the completed report committed to Git and a summary posted to Slack  
**So that** the artifact is permanently stored and immediately accessible

**Acceptance criteria:**
- [ ] `present_summary_for_approval` interrupt node posts summary excerpt and Commit/Discard buttons
- [ ] On approval: `git add`, `git commit` (Conventional Commits format), `git push`
- [ ] On conflict: rebase-and-retry once; fallback to Slack file upload with warning
- [ ] `notify_slack` posts summary excerpt, link to commit, and link to `summary.md`
- [ ] Git commit SHA stored in `gerbil_runs` index

**Technical tasks:**
- Implement `GitPushService` (git add, commit, push, conflict retry)
- Implement `notify_slack` node with Block Kit summary message
- Write integration test (commit to test branch)

---

## Epic 6: Incident Postmortem (UC-1)

> Implement the 8-phase incident analysis workflow, reusing the shared graph skeleton from Epic 5.

---

### US-6.1 — Incident context parsing

**As** an operator  
**I want** the agent to extract the incident time window, affected components, and hypotheses from my description  
**So that** I don't need to fill in a structured form

**Acceptance criteria:**
- [ ] Free-text incident description is parsed to extract: title, time window (start + end), affected components, initial hypotheses
- [ ] All timestamps normalised to ISO8601 UTC
- [ ] Investigation window automatically extended 30 minutes before the reported start time
- [ ] Unrecognised component names trigger a clarification question

**Technical tasks:**
- Implement `parse_incident` node
- Implement `IncidentState` extension fields

---

### US-6.2 — Research phases and hypothesis validation

**As** the incident analysis workflow  
**I want** each research phase to contribute evidence for or against the operator's hypotheses  
**So that** the final postmortem explicitly states which hypotheses are confirmed, probable, or refuted

**Acceptance criteria:**
- [ ] All 7 research phases implemented per [`01-graph-design.md §3.4`](./01-graph-design.md)
- [ ] `hypothesis_results` state field updated after each phase
- [ ] Final synthesis explicitly references each hypothesis with a verdict and supporting metric evidence
- [ ] Cascade failure diagram generated in ASCII art in `summary.md`

**Technical tasks:**
- Implement incident phase nodes (reuse most logic from release report phases)
- Implement hypothesis tracking accumulator
- Implement cascade diagram generator (LLM-prompted)

---

## Epic 7: Code Q&A (UC-3)

---

### US-7.1 — Code question answering

**As** an operator  
**I want** to ask natural-language questions about code changes in `topicusonderwijs/iridium`  
**So that** I can quickly understand what changed between releases without opening the repo

**Acceptance criteria:**
- [ ] Agent answers questions like "what changed in authenticator between 16.5 and 16.7?"
- [ ] Answers cite specific commit SHAs, PR numbers, or file paths
- [ ] GitHub tool calls go through the standard per-call approval gate
- [ ] No artifact written; answer delivered as Slack reply in thread
- [ ] Follow-up questions in the same thread use the existing code Q&A context

**Technical tasks:**
- Implement `code_qa_graph.py` per [`01-graph-design.md §4`](./01-graph-design.md)
- Implement GitHub query planning node
- Implement answer synthesis with citation format

---

## Epic 8: Docs Q&A (UC-4)

---

### US-8.1 — Document ingestion pipeline

**As** the Docs Q&A subsystem  
**I want** the `topicusonderwijs/somtoday-docs` repo indexed into pgvector on initial deployment  
**So that** the retrieval system can answer questions immediately

**Acceptance criteria:**
- [ ] `GitRepoAdapter` fetches all Markdown files from `somtoday-docs` main branch
- [ ] Files chunked with `MarkdownChunker` (500 tokens, 50 overlap)
- [ ] Embeddings stored in `docs_embeddings` pgvector table
- [ ] Initial ingestion completes in < 10 minutes
- [ ] Nightly CronJob re-ingests only changed files (SHA-based deduplication)

**Technical tasks:**
- Implement `CorpusAdapter` interface and `GitRepoAdapter`
- Implement `MarkdownChunker`
- Implement `PgVectorStore`
- Write ingestion Kubernetes Job and CronJob manifests

---

### US-8.2 — Docs Q&A answering

**As** an operator  
**I want** to ask questions about the Somtoday architecture and get answers grounded in the docs  
**So that** I have a searchable knowledge base in Slack

**Acceptance criteria:**
- [ ] Agent retrieves top-5 relevant chunks from pgvector for any question
- [ ] Answer includes citations with source file path and section heading
- [ ] Answer clearly states "not found in documentation" if no relevant chunks are retrieved (score < threshold)
- [ ] No MCP tool calls; no approval gate needed (read-only in-process retrieval)

**Technical tasks:**
- Implement `retrieve()` function with cosine similarity query
- Implement `docs_qa_graph.py`
- Set relevance threshold (e.g., cosine similarity > 0.75)

---

## Epic 9: Hardening and Observability

---

### US-9.1 — Container security hardening

**As** the platform security team  
**I want** all Gerbil containers to run with minimal privileges  
**So that** a compromised container cannot escalate within the cluster

**Acceptance criteria:**
- [ ] All containers run as non-root (`runAsNonRoot: true`, `runAsUser: 1000`)
- [ ] `gerbil-agent` image has no known HIGH or CRITICAL CVEs (Trivy scan in CI)
- [ ] Image digest pinning in production manifests (no `:latest` tags)
- [ ] `read-only` root filesystem where possible

---

### US-9.2 — Structured logging and observability

**As** an ops engineer  
**I want** structured JSON logs from all Gerbil components  
**So that** I can query logs in the cluster's log aggregation system

**Acceptance criteria:**
- [ ] All Python log output is structured JSON (using `structlog` or `python-json-logger`)
- [ ] Each log line includes: `run_id`, `phase`, `tool`, `level`, `timestamp`
- [ ] LangGraph run events (start, node completion, interrupt, end) emitted as log events
- [ ] Approval decisions logged at INFO level (tool name, user_id, decision)

---

### US-9.3 — `@gerbil status` command

**As** an operator  
**I want** to see all active and recent runs for the team channel  
**So that** I can monitor the bot's activity and identify stuck runs

**Acceptance criteria:**
- [ ] `@gerbil status` lists all RUNNING runs and the last 5 COMPLETED/FAILED runs
- [ ] Each entry shows: run_id, intent, started_by, current phase, elapsed time
- [ ] RUNNING runs older than 1 hour show a ⚠️ flag
- [ ] Response formatted as a Slack table (Block Kit section blocks)

---

### US-9.4 — Automated spike: verify MCP SSE transport

**As a developer**  
**I want** to verify before implementation that both Grafana and GitHub MCP servers support the expected SSE port and flags  
**So that** [`ADR-001`](./09-adr/adr-001-mcp-transport.md) assumptions are validated before the team invests in Epic 2

**Acceptance criteria:**
- [ ] Spike result document created confirming or correcting the SSE port/flags for `mcp/grafana`
- [ ] Spike result document confirming or correcting `--transport sse` for `@modelcontextprotocol/server-github`
- [ ] If either server does not support SSE, ADR-001 is updated and the affected server implementation plan revised
- [ ] Spike completed before Epic 2 stories are pulled into a sprint

**Technical tasks:**
- `docker run mcp/grafana --help` and `docker run mcp/grafana -t sse` in a local environment
- `npx @modelcontextprotocol/server-github --help` in a local environment
