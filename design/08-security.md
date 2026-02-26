# Security Design

**Version:** 0.1 (Design)  
**Date:** 2026-02-26  
**Status:** Draft

---

## 1. Overview

The Gerbil AI Suite handles production observability data and code from a regulated Dutch school administration platform (Somtoday / Topicus). It has read-only access to Grafana metrics, Bugsnag errors, and GitHub repositories. It writes only to:
- The `rapports/` Git repository (via deploy key).
- Its own Postgres database (isolated namespace).
- Slack threads initiated by authorized team members.

This document defines the security controls across secrets management, token scoping, network policies, and data handling.

---

## 2. Threat Model Summary

| Threat | Likelihood | Mitigation |
|---|---|---|
| Stolen secret leaks production Grafana token | Medium | Short-lived secrets rotation; read-only access scope |
| Bot abused to exfiltrate production metrics | Low | Slack workspace restriction; per-operator approval log |
| LLM prompt injection via malicious docs content | Low | Retrieval results are injected as structured blocks, not executed |
| Compromised container image | Low | Image digest pinning; vulnerability scanning in CI |
| Unintended write to production systems | Low | All MCP tokens are read-only by policy; deploy key write-scoped only to this repo |
| Credential exposure in LLM context | Medium | Secrets never included in prompts; env-only injection |

---

## 3. Kubernetes Secrets

All sensitive configuration is stored in Kubernetes Secrets. Secrets are never in ConfigMaps, environment-variable defaults, container images, or Git.

| Secret name | Keys | Used by |
|---|---|---|
| `slack-secret` | `SLACK_BOT_TOKEN`, `SLACK_APP_TOKEN`, `SLACK_SIGNING_SECRET` | `gerbil-agent` |
| `grafana-mcp-secret` | `GRAFANA_URL`, `GRAFANA_SERVICE_ACCOUNT_TOKEN` | `grafana-mcp` |
| `smartbear-mcp-secret` | `BUGSNAG_AUTH_TOKEN`, `BUGSNAG_PROJECT_API_KEY` | `smartbear-mcp` sidecar |
| `github-mcp-secret` | `GITHUB_PERSONAL_ACCESS_TOKEN` | `github-mcp` |
| `gitpush-secret` | `GIT_REPO_URL`, `GIT_DEPLOY_KEY` (SSH) | `git-init` init container, `commit_and_push` node |
| `postgres-secret` | `POSTGRES_URL` | `gerbil-agent`, `docs-ingestion` CronJob |
| `llm-secret` | `LLM_PROVIDER`, provider-specific API keys/endpoints | `gerbil-agent` |

### 3.1 Secret creation

Secrets are created manually outside of Git via `kubectl create secret` or via an external secret management system (e.g. HashiCorp Vault, Azure Key Vault CSI driver). The `.env` pattern used in the devcontainer maps directly to these keys.

### 3.2 Rotation policy

| Secret | Rotation frequency | Owner |
|---|---|---|
| Grafana service account token | 90 days | Ops |
| Bugsnag auth token | 90 days | Ops |
| GitHub PAT (MCP read) | 90 days | Engineering |
| GitHub deploy key (write) | 180 days | Engineering |
| Slack bot token | On compromise only | Ops |
| LLM API key | 90 days | Ops |
| Postgres password | 180 days | Ops |

---

## 4. Least-Privilege Token Scopes

### 4.1 Grafana service account

```
Role: Viewer (read-only)
Scope: All dashboards in "Somtoday" folder
No edit, no alerting, no admin access
```

### 4.2 Bugsnag auth token

```
Scope: Error listing + stability score (read-only)
Projects: Somtoday, Somtoday docent, Somtoday leerling only
No project admin, no deletion
```

### 4.3 GitHub PAT — MCP (read-only)

```
Scopes: repo (read only)
Specific repos: topicusonderwijs/iridium, topicusonderwijs/somtoday-docs
No write, no admin, no org-level access
```

Fine-grained PAT (GitHub) is preferred over classic PAT.

### 4.4 GitHub deploy key — Git push (write)

```
Type: SSH deploy key (per-repo)
Repo: this repository (gerbil_ai_suite) only
Access: write to main branch via push
No fork, no admin, no other repos
```

### 4.5 Slack bot token

```
Bot scopes:
  - app_mentions:read
  - channels:history (only channels bot is added to)
  - chat:write
  - files:write
  - reactions:write
  - users:read (for user_id → name resolution)
No admin, no workspace-level read
```

---

## 5. Namespace Isolation

All Gerbil components run in the **`gerbil` namespace**. Kubernetes RBAC:

```yaml
# ServiceAccount for gerbil-agent
apiVersion: v1
kind: ServiceAccount
metadata:
  name: gerbil-agent-sa
  namespace: gerbil

# No ClusterRole — namespace-scoped only
# No access to other namespaces or cluster-level resources
```

The `gerbil-agent` service account has no permissions outside its namespace. It does not access Kubernetes API for any other purpose than health self-reporting.

---

## 6. Network Policies

```yaml
# Deny all ingress to the gerbil namespace by default
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: deny-all-ingress
  namespace: gerbil
spec:
  podSelector: {}
  policyTypes: [Ingress]

# Allow gerbil-agent to reach MCP services within namespace
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-agent-to-mcp
  namespace: gerbil
spec:
  podSelector:
    matchLabels: { app: gerbil-agent }
  policyTypes: [Egress]
  egress:
    - to:
        - namespaceSelector:
            matchLabels: { kubernetes.io/metadata.name: gerbil }
      ports:
        - port: 8080    # grafana-mcp
        - port: 3000    # github-mcp
        - port: 5432    # postgres
    - to: []            # Allow egress to external APIs (Slack, Grafana, GitHub, Bugsnag)
      ports:
        - port: 443
```

MCP service pods only allow ingress from `gerbil-agent`:

```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-grafana-mcp-from-agent
  namespace: gerbil
spec:
  podSelector:
    matchLabels: { app: grafana-mcp }
  policyTypes: [Ingress]
  ingress:
    - from:
        - podSelector:
            matchLabels: { app: gerbil-agent }
      ports:
        - port: 8080
```

---

## 7. Data Handling

### 7.1 What data is processed

| Data category | Source | In LLM context? | Stored? |
|---|---|---|---|
| Production metrics (aggregated) | Grafana / Prometheus | Yes, as metric values | In research files (Git) |
| Error messages + stack traces | Bugsnag | Yes | In research files (Git) |
| Code changes (diff, commits) | GitHub | Yes, as text snippets | Not stored |
| Docs content | somtoday-docs repo | Yes, as retrieved chunks | Vector store (Postgres) |
| Slack message content | Slack | Yes (for context) | Checkpoint (Postgres, 30-day TTL) |
| User IDs | Slack | Minimal (approver IDs in audit log) | Approval log (Postgres, 1 year) |

### 7.2 Data residency

The LLM API calls send metric values, error messages, and code snippets to the LLM provider. For a Dutch school platform, this means:
- **Azure OpenAI** with EU data residency is the preferred LLM backend.
- Contract review with LLM provider must confirm no training use of API data.
- Staff (not student) data only flows through the system.

### 7.3 Student data

No student personal data (names, BSN, grades) is accessible via Grafana metrics or production error stack traces. If error stack traces ever contain personal data, the Bugsnag project should be reviewed and data scrubbing enabled at the Bugsnag level before this tool is used.

---

## 8. Image Security

| Control | Implementation |
|---|---|
| Image vulnerability scanning | CI pipeline scans `gerbil-agent` image with Trivy on every build |
| Image digest pinning | Production manifests reference `image@sha256:...` not `:latest` |
| No root containers | All containers run as non-root (`runAsNonRoot: true`, `runAsUser: 1000`) |
| Read-only root filesystem | Enabled for `grafana-mcp` and `github-mcp`; `gerbil-agent` needs writable `/tmp` |
| Dependency audit | Python and Node.js dependency audit runs in CI (`pip-audit`, `npm audit`) |

---

## 9. Approval Governance

The per-tool-call approval system (see [`03-slack-interface.md §4`](./03-slack-interface.md)) is itself a security control:
- An operator must explicitly authorise each MCP tool call or grant session-wide consent.
- Approval decisions are recorded in the `approval_log` (see [`04-state-and-memory.md §9`](./04-state-and-memory.md)) with `user_id` and timestamp.
- Session-wide consent cannot be granted for an entire class of tools; it is valid for one run only.
- The audit log is immutable (append-only in the Postgres checkpoint; never edited by the agent).

---

## 10. Incident Response

If a secret is suspected compromised:
1. Rotate the secret immediately via the provider (Grafana, GitHub, etc.).
2. Update the corresponding Kubernetes Secret: `kubectl create secret generic <name> --from-literal=<key>=<new-value> -n gerbil --dry-run=client -o yaml | kubectl apply -f -`.
3. Restart affected Deployments: `kubectl rollout restart deployment/<name> -n gerbil`.
4. Review `gerbil_runs` audit log for suspicious activity in the preceding 30 days.
