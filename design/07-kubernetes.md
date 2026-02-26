# Kubernetes Deployment Design

**Version:** 0.1 (Design)  
**Date:** 2026-02-26  
**Status:** Draft

---

## 1. Overview

All components run in the **`gerbil` namespace** in the production Kubernetes cluster (`somtoday`). The deployment is intentionally small for MVP: a single `gerbil-agent` Deployment with one replica, supporting controlled scale-out in future sprints.

---

## 2. Component Inventory

| Component | Kind | Replicas (MVP) | Notes |
|---|---|---|---|
| `gerbil-agent` | Deployment | 1 | LangGraph orchestrator + Slack Bolt app + SmartBear MCP sidecar |
| `grafana-mcp` | Deployment | 1 | Grafana MCP server (HTTP/SSE) |
| `github-mcp` | Deployment | 1 | GitHub MCP server (HTTP/SSE) |
| `gerbil-postgres` | StatefulSet | 1 | PostgreSQL 16 (checkpoints + vector store) |
| `docs-ingestion` | CronJob | — | Nightly docs re-indexing (00:00 CET) |
| `git-init` | InitContainer | — | Clone git repo into PVC at pod startup |
| `rapports-pvc` | PersistentVolumeClaim | — | 5 GiB ReadWriteOnce |
| `postgres-pvc` | PersistentVolumeClaim | — | 10 GiB ReadWriteOnce |

---

## 3. Network Topology

```
Internet (Slack Events API)
        │
        │ (Slack Socket Mode — outbound TCP 443 from pod)
        ▼
┌─────────────────────────────────────────────────────────────────┐
│  Namespace: gerbil                                              │
│                                                                 │
│  ┌──────────────────────────────────────────────────────────┐   │
│  │  gerbil-agent Pod                                        │   │
│  │  ┌───────────────────┐   ┌──────────────────────────┐   │   │
│  │  │  gerbil-agent     │   │  smartbear-mcp (sidecar)  │   │   │
│  │  │  container        │◄──│  (stdio bridge)           │   │   │
│  │  └──────┬────────────┘   └──────────────────────────┘   │   │
│  └─────────┼────────────────────────────────────────────────┘   │
│            │                                                     │
│     ┌──────┼──────────────────────┐                             │
│     │      │                      │                             │
│     ▼      ▼                      ▼                             │
│  grafana-mcp-svc          github-mcp-svc          postgres-svc  │
│  (ClusterIP :8080)        (ClusterIP :3000)        (:5432)      │
│     │                         │                                  │
│     ▼                         ▼                                  │
│  grafana-mcp Pod          github-mcp Pod                        │
│                                                                 │
│  rapports-pvc (RWO, 5 GiB)   postgres-pvc (RWO, 10 GiB)       │
└─────────────────────────────────────────────────────────────────┘
        │                              │
        ▼                              ▼
  Grafana (external)         GitHub API (external)
  Bugsnag API (external)
```

All inter-pod communication is **ClusterIP only** — no Ingress or LoadBalancer required. Slack uses Socket Mode (outbound connection from the pod), so no inbound firewall rules are needed.

---

## 4. Pod Specifications

### 4.1 `gerbil-agent` Pod

```yaml
spec:
  initContainers:
    - name: git-init
      image: alpine/git:latest
      command:
        - sh
        - -c
        - |
          if [ ! -d /rapports/.git ]; then
            git clone $GIT_REPO_URL /rapports
          else
            git -C /rapports pull --rebase
          fi
      env:
        - name: GIT_REPO_URL
          valueFrom:
            secretKeyRef:
              name: gitpush-secret
              key: GIT_REPO_URL
      volumeMounts:
        - name: rapports-volume
          mountPath: /rapports

  containers:
    - name: gerbil-agent
      image: ghcr.io/topicusonderwijs/gerbil-agent:latest
      ports:
        - containerPort: 3000      # health check
      env:
        - name: SLACK_BOT_TOKEN
          valueFrom: { secretKeyRef: { name: slack-secret, key: SLACK_BOT_TOKEN } }
        - name: SLACK_APP_TOKEN
          valueFrom: { secretKeyRef: { name: slack-secret, key: SLACK_APP_TOKEN } }
        - name: SLACK_SIGNING_SECRET
          valueFrom: { secretKeyRef: { name: slack-secret, key: SLACK_SIGNING_SECRET } }
        - name: POSTGRES_URL
          valueFrom: { secretKeyRef: { name: postgres-secret, key: POSTGRES_URL } }
        - name: GRAFANA_MCP_URL
          value: "http://grafana-mcp-svc.gerbil.svc.cluster.local:8080/sse"
        - name: GITHUB_MCP_URL
          value: "http://github-mcp-svc.gerbil.svc.cluster.local:3000/sse"
        - name: BUGSNAG_AUTH_TOKEN
          valueFrom: { secretKeyRef: { name: smartbear-mcp-secret, key: BUGSNAG_AUTH_TOKEN } }
        - name: LLM_PROVIDER
          value: "azure_openai"             # or "openai" / "anthropic" — set per environment
        - name: AZURE_OPENAI_ENDPOINT
          valueFrom: { secretKeyRef: { name: llm-secret, key: AZURE_OPENAI_ENDPOINT } }
        - name: AZURE_OPENAI_API_KEY
          valueFrom: { secretKeyRef: { name: llm-secret, key: AZURE_OPENAI_API_KEY } }
        - name: RAPPORTS_DIR
          value: /rapports
      volumeMounts:
        - name: rapports-volume
          mountPath: /rapports
      resources:
        requests:
          cpu: "250m"
          memory: "512Mi"
        limits:
          cpu: "1000m"
          memory: "1Gi"
      readinessProbe:
        httpGet:
          path: /health
          port: 3000
        initialDelaySeconds: 10
        periodSeconds: 15
      livenessProbe:
        httpGet:
          path: /health
          port: 3000
        initialDelaySeconds: 30
        periodSeconds: 30

    - name: smartbear-mcp
      image: node:22-slim
      command: ["npx", "-y", "@smartbear/mcp@latest"]
      env:
        - name: BUGSNAG_AUTH_TOKEN
          valueFrom: { secretKeyRef: { name: smartbear-mcp-secret, key: BUGSNAG_AUTH_TOKEN } }
      stdin: true
      resources:
        requests:
          cpu: "100m"
          memory: "256Mi"
        limits:
          cpu: "500m"
          memory: "512Mi"

  volumes:
    - name: rapports-volume
      persistentVolumeClaim:
        claimName: rapports-pvc
```

### 4.2 `grafana-mcp` Pod

```yaml
containers:
  - name: grafana-mcp
    image: mcp/grafana:latest
    args: ["-t", "sse"]
    ports:
      - containerPort: 8080
    env:
      - name: GRAFANA_URL
        valueFrom: { secretKeyRef: { name: grafana-mcp-secret, key: GRAFANA_URL } }
      - name: GRAFANA_SERVICE_ACCOUNT_TOKEN
        valueFrom: { secretKeyRef: { name: grafana-mcp-secret, key: GRAFANA_SERVICE_ACCOUNT_TOKEN } }
    resources:
      requests: { cpu: "100m", memory: "128Mi" }
      limits: { cpu: "500m", memory: "512Mi" }
```

### 4.3 `github-mcp` Pod

```yaml
containers:
  - name: github-mcp
    image: node:22-slim
    command: ["npx", "-y", "@modelcontextprotocol/server-github@latest"]
    args: ["--transport", "sse", "--port", "3000"]
    ports:
      - containerPort: 3000
    env:
      - name: GITHUB_PERSONAL_ACCESS_TOKEN
        valueFrom: { secretKeyRef: { name: github-mcp-secret, key: GITHUB_PERSONAL_ACCESS_TOKEN } }
    resources:
      requests: { cpu: "100m", memory: "256Mi" }
      limits: { cpu: "500m", memory: "512Mi" }
```

---

## 5. Services

```yaml
# grafana-mcp-svc
apiVersion: v1
kind: Service
metadata:
  name: grafana-mcp-svc
  namespace: gerbil
spec:
  selector: { app: grafana-mcp }
  ports: [{ port: 8080, targetPort: 8080 }]
  type: ClusterIP

# github-mcp-svc
apiVersion: v1
kind: Service
metadata:
  name: github-mcp-svc
  namespace: gerbil
spec:
  selector: { app: github-mcp }
  ports: [{ port: 3000, targetPort: 3000 }]
  type: ClusterIP

# postgres-svc
apiVersion: v1
kind: Service
metadata:
  name: postgres-svc
  namespace: gerbil
spec:
  selector: { app: gerbil-postgres }
  ports: [{ port: 5432, targetPort: 5432 }]
  type: ClusterIP
```

---

## 6. Persistent Volumes

| PVC | Size | Access Mode | Used by |
|---|---|---|---|
| `rapports-pvc` | 5 GiB | ReadWriteOnce | `gerbil-agent` (reports workspace) |
| `postgres-pvc` | 10 GiB | ReadWriteOnce | `gerbil-postgres` (state + vectors) |

---

## 7. Resource Summary

| Component | CPU req | CPU limit | Mem req | Mem limit |
|---|---|---|---|---|
| gerbil-agent (main) | 250m | 1000m | 512Mi | 1Gi |
| smartbear-mcp (sidecar) | 100m | 500m | 256Mi | 512Mi |
| grafana-mcp | 100m | 500m | 128Mi | 512Mi |
| github-mcp | 100m | 500m | 256Mi | 512Mi |
| gerbil-postgres | 250m | 1000m | 512Mi | 2Gi |
| **Total** | **800m** | **3500m** | **1664Mi** | **4608Mi** |

---

## 8. Scaling Model (MVP)

**Single replica per Deployment.** Concurrent runs are bounded by the in-process queue (max 2 concurrent, as defined in [`03-slack-interface.md §9`](./03-slack-interface.md)).

Scale-out strategy (post-MVP):
- The bottleneck is the SmartBear MCP sidecar (stdio, one pod = one connection). To scale, migrate SmartBear to HTTP/SSE so the sidecar constraint is removed.
- `gerbil-agent` can then scale to N replicas with shared Postgres checkpointer.
- `grafana-mcp` and `github-mcp` can scale independently via HPA on CPU.

---

## 9. Image Registry

| Image | Registry | Notes |
|---|---|---|
| `gerbil-agent` | `ghcr.io/topicusonderwijs/gerbil-agent` | Built in CI; versioned tags |
| `mcp/grafana` | Private mirror of Docker Hub `mcp/grafana` | Mirror to avoid rate limits |
| `node:22-slim` | Docker Hub (or private mirror) | Used for SmartBear + GitHub MCP |
| `postgres:16-alpine` | Docker Hub (or private mirror) | |
| `alpine/git:latest` | Docker Hub (or private mirror) | Init container |

---

## 10. Deployment Strategy

**`RollingUpdate`** with `maxUnavailable: 0` and `maxSurge: 1` for `gerbil-agent`.  
In-flight LangGraph runs survive pod transitions because state is persisted in Postgres; the new pod resumes via `PostgresSaver` on startup (see [`04-state-and-memory.md §6`](./04-state-and-memory.md)).

---

## 11. Health Checks

`gerbil-agent` exposes `GET /health` returning:

```json
{
  "status": "ok",
  "mcp": {
    "grafana": "connected",
    "smartbear": "connected",
    "github": "connected"
  },
  "postgres": "connected",
  "slack": "connected"
}
```

A degraded MCP connection returns `"status": "degraded"` but does **not** cause readiness probe failure (runs continue but affected phases will DATA_GAP).
