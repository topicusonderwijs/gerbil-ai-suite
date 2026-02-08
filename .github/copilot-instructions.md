# Copilot Instructions for Gerbil AI Suite

## Project Overview

This is an **MCP server orchestration workspace** for AI-assisted DevOps reporting for **Somtoday** — a Dutch school administration platform. It provides GitHub Copilot access to Grafana metrics and Bugsnag errors via Model Context Protocol (MCP) servers running in Docker.

**Primary purpose:** Generate release reports and incident postmortems by correlating data from GitHub, Grafana, and Bugsnag.

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│  GitHub Copilot (VS Code)                                   │
└────────────────────────┬────────────────────────────────────┘
                         │ MCP Protocol (stdio)
         ┌───────────────┼───────────────┐
         ▼               ▼               ▼
┌─────────────┐  ┌─────────────┐  ┌─────────────┐
│ Grafana MCP │  │ SmartBear   │  │ GitHub MCP  │
│  (Docker)   │  │ MCP (npx)   │  │  (builtin)  │
└─────────────┘  └─────────────┘  └─────────────┘
```

- **MCP config location:** `~/.vscode-server/data/User/mcp.json` (auto-configured by devcontainer)
- **Credentials:** `.env` file in workspace root (never committed)

## Key Directories

| Path | Purpose |
|------|---------|
| `rapports/` | Generated reports (release reports, postmortems) |
| `template/` | Markdown templates for report generation |
| `.github/agents/` | Copilot agent configurations (reusable prompts) |
| `.devcontainer/` | Container setup and MCP auto-configuration scripts |

## Report Generation Workflow

Reports are generated with a **research-first approach** to handle large MCP data volumes. Each report type creates a directory with research subfiles before synthesizing the final summary.

### Directory Structure
```
rapports/[report_type]_[date]_[subject]/
├── research/
│   ├── database.md      # PgBouncer, PostgreSQL metrics
│   ├── cloudflare.md    # Tunnel health, edge metrics
│   ├── kubernetes.md    # Pod health, deployments
│   ├── proxy.md         # Traefik ingress, routing, request metrics
│   ├── application.md   # Response times, throughput
│   └── exceptions.md    # Bugsnag errors, log errors
└── summary.md           # Final synthesized report
```

### Release Reports
When asked to generate a **release report**:
1. Use the agent defined in [.github/agents/release_rapport.agent.md](.github/agents/release_rapport.agent.md)
2. Query GitHub (`topicusonderwijs/iridium`) for release tags and changes
3. Query Bugsnag for projects containing "somtoday" only
4. Query Grafana dashboards in the "Somtoday" folder, filter on `productie` labels
5. **Write research files immediately after each domain query**
6. Save final report to `rapports/release_YYYY-MM-DD_VERSION/summary.md`

### Incident Postmortems
When asked to **analyze a production incident** or generate a **postmortem**:
1. Use the agent defined in [.github/agents/incident_analysis.agent.md](.github/agents/incident_analysis.agent.md)
2. User provides: incident description, time window, affected systems, and initial hypotheses
3. Agent performs comprehensive analysis across Grafana metrics, Bugsnag errors, and relevant code
4. **Write research files immediately after each domain query**
5. Follow the cascade analysis pattern
6. Use the template at [template/postmortem.md](template/postmortem.md)
6. Include timeline tables, metrics analysis with exact timestamps, and root cause diagrams
7. Always document **data gaps** (unavailable metrics) explicitly
8. Validate or refute user's hypotheses with evidence
9. Save to `rapports/postmortem_YYYY-MM-DD_TITLE.md`

## MCP Tool Usage Patterns

### Grafana Queries
- **Primary Datasource:** `PBFA97CFB590B2093` (Prometheus - default, most metrics)
- **Secondary Datasource:** `RU1hwHA4k` (Grafana Cloud Metrics - custom Wildfly metrics)

**Essential label filters:**
| Label | Value | Environment |
|-------|-------|-------------|
| `kubernetes_cluster` | `somtoday` | Production |
| `kubernetes_cluster` | `som-core-prod-h9g` | Acceptance & Test |
| `businessline` | `somtoday` | All environments |
| `environment` | `productie` / `acceptatie` / `test` | Specific env |

### Key Dashboards

| Dashboard | UID | Purpose |
|-----------|-----|---------|
| **Somtoday status overview** | `K3Q86qtGz` | Main ops dashboard - environment health, response times, DB status |
| **Somtoday status** | `RnaE_aGZk` | Detailed component metrics - threads, sessions, request times |
| **Active Alerts Overview** | `be4mcwmkdce80f` | Current alerts by severity |
| **Database Quickview** | `J8vwk3DMk` | PgBouncer throughput, connections |
| **Infinispan caches** | `eT3sI56nk` | Application cache hit ratios |
| **Cloudflared Tunnel** | `2WhbDNm7z` | Cloudflare tunnel connections, requests, errors (use `kubernetes_cluster=somtoday` for prod) |
| **Traefik v3** | `rCn92aUGp` | Ingress controller metrics - request rates, latencies, error codes (use `k8s_cluster=somtoday`, `k8s_namespace=traefik`) |
| **Postgres Exporters** | `LCKWasdf` | Deep PostgreSQL metrics - locks, transactions, tuples, replication lag |
| **PostgreSQL PgBouncer** | `ZEGmB3lik` | PgBouncer connection pools - active/waiting/idle per user/database |
| **NATS JetStream** | `FImG4sInk` | Message streams, consumers, pending messages (use `businessline=somtoday`) |

### Important Metrics (PromQL)

**Health & Availability:**
```promql
up{environment="productie", businessline="somtoday"}
```

**Request throughput (Traefik):**
```promql
sum(rate(traefik_service_requests_total{kubernetes_cluster="somtoday", exported_service=~".*-api-ws-rest-.*"}[1m]))
```

**Response times (99th percentile):**
```promql
histogram_quantile(0.99, sum(irate(traefik_service_request_duration_seconds_bucket{kubernetes_cluster="somtoday", exported_service=~".*-oop-sis-ui-.*"}[1m])) by (le))
```

**Thread utilization:**
```promql
max((wildfly_io_busy_task_thread_count{kubernetes_cluster="somtoday", environment="productie"} + wildfly_io_queue_size) / wildfly_io_max_pool_size) by (component) * 100
```

**Database connections (PgBouncer):**
```promql
sum(pgbouncer_pools_client_active_connections{database="productie", instance=~"pg-prod-w16.*"})
sum(pgbouncer_pools_client_waiting_connections{database="productie", instance=~"pg-prod-w16.*"})
```

**Active users:**
```promql
wildfly_request_active_users_5m{businessline="somtoday", component="sis-ui", environment="productie"}
```

### Application Components
Key `component` label values for filtering:
- `sis-ui` — Main SIS web interface
- `ws-rest` — Student REST API
- `docent-rest` — Teacher REST API  
- `authenticator` — Login/authentication service
- `rest-auth` — REST authentication
- `connect-rest` — Connect API
- `mmp-rest` — MMP API

### Bugsnag Projects
Query these specific projects (not a wildcard search):

| Project ID | Project | Description |
|------------|---------|-------------|
| **543ce4797765623fb900011d** | **Somtoday** | Main application and backend |
| **59d20374c943ea002679e025** | **Somtoday docent** | Angular frontend for teachers |
| **65e09a58bf784d00154ac51a** | **Somtoday leerling** | Angular mobile app for students |

### Bugsnag Environment Filtering
**CRITICAL:** Always filter by correct `app.release_stage` when investigating production issues.

⚠️ **IMPORTANT: The Backend and Frontend projects use DIFFERENT release stage names for production:**

| Project | Project ID | Production `app.release_stage` |
|---------|-----------|-------------------------------|
| **Somtoday** (Backend) | `543ce4797765623fb900011d` | `"production"` |
| **Somtoday Docent** (Frontend) | `59d20374c943ea002679e025` | `"productie"` |
| **Somtoday Leerling** (Frontend) | `65e09a58bf784d00154ac51a` | `"productie"` |

**All environment stage values:**

| Environment | Backend (`Somtoday`) | Frontend (`Docent` / `Leerling`) |
|-------------|---------------------|----------------------------------|
| **Production** | `"production"` | `"productie"` |
| **Acceptance** | `"acceptatie"` | `"acceptatie"` |
| **Test** | `"test"` | `"test"` |
| **Inkijk** | `"inkijk"` / `"inkijk2"` | — |
| **PR** | `"pr"` | — |
| **Regressie** | `"regressie"` | — |
| **Nightly** | `"nightly"` | — |
| **Native** | — | `"native"` |

**Example production error filters:**
```json
// For Somtoday Backend (project 543ce4797765623fb900011d):
{
  "app.release_stage": [{"type": "eq", "value": "production"}],
  "event.since": [{"type": "eq", "value": "2026-01-31T10:00:00Z"}],
  "event.before": [{"type": "eq", "value": "2026-01-31T16:00:00Z"}]
}

// For Somtoday Docent / Leerling (frontend projects):
{
  "app.release_stage": [{"type": "eq", "value": "productie"}],
  "event.since": [{"type": "eq", "value": "2026-01-31T10:00:00Z"}],
  "event.before": [{"type": "eq", "value": "2026-01-31T16:00:00Z"}]
}
```

**Analysis Guidelines:**
- ⚠️ **Always use the correct release stage per project** — using `"productie"` on the Backend will return 0 results!
- Compare errors between release versions using timestamp AND environment filters
- Focus on **new errors** introduced in a release, not pre-existing ones
- **Never correlate non-production errors with production performance issues**
- Always verify `app.release_stage` in error details before drawing conclusions

### Database Reference
For context when analyzing database-related incidents:

| Host | Prometheus `instance` label | Purpose |
|------|----------------------------|---------|
| `pg-prod-w16` (set 1) | `pg-prod-w16.prod.core.somtoday.pdc.topicus.education` | Production DB (primary set 1) |
| `pg-prod-2ve` (set 2) | `pg-prod-2ve.prod.core.somtoday.pdc.topicus.education` | Production DB (primary set 2) |
| `pg-prod-h5j` (standby) | `pg-prod-h5j.prod.core.somtoday.pdc.topicus.education` | Production standby |
| `pg-audit-9a8` | `pg-audit-9a8.prod.core.somtoday.pdc.topicus.education` | Audit logging |
| `pg-accp-a1g` | `pg-accp-a1g.nonprod.core.somtoday.pdc.topicus.education` | Acceptance |
| `pg-test-8tz` | `pg-test-8tz.vl21.pdc.topicus.education` | Test |
| `pg-inkijk-d1q` | `pg-inkijk-d1q.vl21.pdc.topicus.education` | Inkijk (read-only access) |

**Ports:** PostgreSQL metrics on `:9187` (or `:9188`/`:9189` for replicas), PgBouncer on `:9110`

## Conventions

- **Default timezone:** Central European Time (CET/CEST) — all timestamps default to CET unless otherwise specified
- **Report filenames:** Use underscore-separated dates and versions: `release_2026-01-09_16.6.md`
- **Time format:** Always include both CET and UTC in timelines
- **Missing data:** Explicitly state "Data unavailable from [Source]" rather than omitting
- **Metrics tables:** Include trend indicators (✅ Normal, ⚠️ Elevated, 🔴 Critical)

## Credentials Setup

If MCP tools aren't working, guide users to run:
```bash
bash .devcontainer/setup-env.sh  # Interactive credential setup
bash .devcontainer/setup-mcp.sh  # Reconfigure MCP servers
```
Then reload VS Code window.

## Git Commit Conventions

Use **semantic commit messages** following the [Conventional Commits](https://www.conventionalcommits.org/) specification:

### Format
```
<type>(<scope>): <description>

[optional body]

[optional footer(s)]
```

### Types
| Type | Description |
|------|-------------|
| `feat` | A new feature |
| `fix` | A bug fix |
| `docs` | Documentation only changes |
| `style` | Changes that don't affect meaning (formatting, whitespace) |
| `refactor` | Code change that neither fixes a bug nor adds a feature |
| `perf` | Performance improvement |
| `test` | Adding or correcting tests |
| `build` | Changes to build system or dependencies |
| `ci` | Changes to CI configuration |
| `chore` | Other changes that don't modify src or test files |
| `revert` | Reverts a previous commit |

### Scopes (Project-specific)
| Scope | Description |
|-------|-------------|
| `reports` | Changes to report templates or generated reports |
| `postmortem` | Postmortem-related changes |
| `release` | Release report-related changes |
| `mcp` | MCP server configuration |
| `grafana` | Grafana queries or dashboard references |
| `bugsnag` | Bugsnag integration |
| `agents` | Copilot agent configurations |
| `devcontainer` | Development container setup |

### Examples
```bash
# New postmortem report
docs(postmortem): add JEE10 ws-rest incident analysis 2026-01-15

# Update copilot instructions
docs(agents): add semantic commit conventions

# Fix MCP configuration
fix(mcp): correct Grafana datasource UID

# New feature in report generation
feat(reports): add cascade failure diagram template
```

### Breaking Changes
Indicate breaking changes with `!` after the type/scope or in the footer:
```bash
feat(mcp)!: migrate to MCP v2 protocol

BREAKING CHANGE: requires updated mcp.json configuration
```
