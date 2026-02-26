# Output Strategy

**Version:** 0.1 (Design)  
**Date:** 2026-02-26  
**Status:** Draft

---

## 1. Overview

Generated artifacts follow a **hybrid strategy**: durable storage in Git (the existing `rapports/` discipline) plus immediate human-readable delivery in Slack (summary excerpts and direct links). This preserves the existing audit trail and report structure while making results available in the team's primary communication channel without requiring file downloads.

---

## 2. Artifact Types

| Artifact | Format | Created by | Persisted |
|---|---|---|---|
| Research files | Markdown (`research/*.md`) | Phase nodes (written immediately after each phase) | Git + PVC |
| Summary report | Markdown (`summary.md`) | `synthesise` node (final phase) | Git + PVC |
| Slack excerpt | Plain text / Block Kit | `notify_slack` node | Slack only |
| Approval audit log | JSON (embedded in checkpoint) | `execute_mcp_tool` wrapper | Postgres |
| Run index entry | SQL row (`gerbil_runs`) | Run lifecycle hooks | Postgres |

---

## 3. Directory Structure (unchanged from current workflow)

```
rapports/
├── release_2026-02-25_16.7/
│   ├── research/
│   │   ├── database.md
│   │   ├── cloudflare.md
│   │   ├── kubernetes.md
│   │   ├── proxy.md
│   │   ├── application.md
│   │   └── exceptions.md
│   └── summary.md
└── postmortem_2026-02-20_ws-rest-latency/
    ├── research/
    │   └── ...
    └── summary.md
```

Naming convention is preserved from the existing agent workflows:
- Release: `release_YYYY-MM-DD_VERSION`
- Postmortem: `postmortem_YYYY-MM-DD_TITLE`

No changes to the naming scheme; existing reports remain valid and browsable.

---

## 4. Git Persistence Flow

### 4.1 PVC-backed workspace

The `rapports/` directory is mounted on a **Persistent Volume Claim (PVC)** inside the `gerbil-agent` pod. Phase nodes write research files directly to this volume.

### 4.2 Git commit and push

After `synthesise` produces `summary.md` and the operator approves the commit (see [`03-slack-interface.md §4.1`](./03-slack-interface.md)):

```
[commit_and_push node]

1. git add rapports/<DIR>/
2. git commit -m "docs(reports): <intent> <version/title> <date>"
   (follows Conventional Commits format from copilot-instructions.md)
3. git push origin main
```

**Credentials:** A deploy key or GitHub App installation token with write access to this repository, stored as `github-gitpush-secret` K8s Secret. This is **separate** from the GitHub MCP PAT (read-only repository access).

### 4.3 Commit message conventions

| Use case | Commit message format |
|---|---|
| Release report | `docs(release): release report YYYY-MM-DD VERSION` |
| Postmortem | `docs(postmortem): postmortem YYYY-MM-DD TITLE` |

### 4.4 Conflict handling

If `git push` fails (concurrent push):
1. `git pull --rebase`
2. Retry push once.
3. If still failing: upload `summary.md` as a Slack file attachment with warning message; log conflict in run record.

### 4.5 Git repo configuration

The PVC is initialised with a `git clone` of this repository at pod startup. A lightweight init container handles the clone and credential setup so the main container's working directory is always a valid git worktree.

---

## 5. Slack Delivery

### 5.1 Summary excerpt

After a successful Git commit, the `notify_slack` node posts to the originating Slack thread:

```
📄 Release Report — 16.7.0
──────────────────────────────────────────
Deployment: 2026-02-25 14:00 CET (JEE10, no rollbacks)
Comparison: 16.7.0 vs 16.6.2

🔵 Infrastructure
  Kubernetes: All pods healthy. No OOMKills.
  Database:   Active connections stable (avg 42 vs 39 prev). ✅
  Cloudflare: Tunnel healthy, 0 errors. ✅

🔵 Application Performance
  p99 latency sis-ui:   210ms vs 195ms (+8%) ⚠️
  p99 latency ws-rest:  145ms vs 140ms (+4%) ✅
  5xx error rate:       0.02% vs 0.03% (−33%) ✅

🔵 Stability (Bugsnag)
  New errors: 2 (backend), 0 (docent), 1 (leerling)
  Stability:  99.1% (same as prev) ✅

Verdict: ✅ Go

🔗 Full report: https://github.com/.../rapports/release_2026-02-25_16.7/summary.md
   Commit: abc1234
```

### 5.2 Research file progress

After each phase node writes its research file, a compact progress update is posted:

```
📋 Phase 3 complete — Database (PgBouncer)
   Active connections: 42 avg (prev: 39). Waiting: 0. ✅
   → Saved to research/database.md
```

### 5.3 File uploads (fallback)

If Git push fails, the `summary.md` is uploaded directly to Slack as a file attachment with a warning banner.

---

## 6. Research File Writing Discipline

This matches the requirement from the existing agent workflows: **write immediately after each phase, do not accumulate**.

| Requirement | Mechanism |
|---|---|
| Write after each phase | Each phase node ends with a `write_research_file()` call before transitioning |
| File written to PVC | Direct filesystem write to `artifact_dir/research/<domain>.md` |
| Contents: raw data + queries | Research file template from existing agent (see [`release_rapport.agent.md`](../.github/agents/release_rapport.agent.md)) preserved |
| Summary generated last | `synthesise` node reads all research files from PVC; synthesis prompt references them |

---

## 7. Code Q&A and Docs Q&A Output

These use cases produce **conversational Slack replies only** — no Git artifact, no PVC write.

| Use case | Output |
|---|---|
| Code Q&A | Inline Slack message with cited commit SHAs / PR numbers |
| Docs Q&A | Inline Slack message with cited source document + section links |

---

## 8. Future: Additional Output Channels

The output strategy is designed to be extended without architectural changes. Future destinations:

| Destination | Trigger | Notes |
|---|---|---|
| Confluence page | Post-summary node (optional) | Publish `summary.md` to a Confluence space via REST API |
| Email / PDF | Manual export | Out of scope for this system |
| GitHub PR comment | Code Q&A context | Post diff analysis as a PR review comment |
| Grafana annotation | Incident postmortem | Mark incident window on Grafana dashboards |
