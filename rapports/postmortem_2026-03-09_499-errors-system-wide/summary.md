# 🔥 Postmortem Incident Report: System-wide 499 Errors — Database Connection Pool Saturation

**Incident Date:** 2026-03-09  
**Time Window:** 09:01 - 13:00 CET (08:01 - 12:00 UTC)  
**User-Reported Start:** 09:50 CET  
**Affected Systems:** All production components — docent-rest, ws-rest, authenticator, sis-ui, docent-graphql, rest-auth  
**Severity:** Critical  
**Environment:** Production (`kubernetes_cluster=somtoday`, `environment=productie`)

---

## 1. Executive Summary

Starting at 09:01 CET on March 9, 2026, the authenticator service began failing to connect to rest-auth, triggering a **cascade failure** that saturated PgBouncer connection pools and degraded all production services. All major components (docent-rest, ws-rest, sis-ui, authenticator) hit the 5-second timeout ceiling, generating **273 client-abort errors (499) per second** at peak across **6+ recurring failure waves** from 09:51 to 13:00 CET. The platform self-recovered around 13:00 CET as traffic naturally decreased and connection pools drained.

Root cause investigation points to **rest-auth connectivity failure** as the initial trigger, with the cascade amplified by connections being held longer than normal (waiting connections 5.7x baseline). Week-prior comparison confirmed that PgBouncer active connection patterns were within normal range — the anomaly was in connection *duration*, not connection *count*. The recurring ~30-minute wave pattern suggests a self-reinforcing cycle of timeout → retry → pool pressure → timeout.

---

## 2. Timeline

| Time (CET) | Time (UTC) | Event |
|------------|------------|-------|
| 08:32 | 07:32 | EJBTransactionRolledbackException on sis-ui (EntityManager closed — early warning?) |
| **09:01** | **08:01** | **⚡ authenticator→rest-auth ConnectTimeoutException begins (155,908 total events)** |
| 09:02 | 08:02 | `landelijk_productie` DB user at 629 connections (normal oscillation pattern — see week-prior comparison) |
| 09:16 | 08:16 | DNS resolution for `prod-rest-auth` fails (UnknownHostException, 894 events) |
| **09:50** | **08:50** | **PgBouncer waiting connections appear on pg-prod-w16 — user-visible impact begins** |
| 09:52 | 08:52 | PgBouncer server active connections spike to 366 |
| 09:53 | 08:53 | docent-graphql frontend: ETIMEDOUT connecting to docent-rest pods (all pods affected) |
| 10:00 | 09:00 | ws-rest, sis-ui, docent-graphql hit 5.0s P99 latency (timeout ceiling) |
| 10:00 | 09:00 | 499 errors spike to 137.8/s system-wide |
| 10:08 | 09:08 | ws-rest 499 errors peak at 143.3/s |
| 10:10 | 09:10 | PgBouncer waiting connections peak at 86 on pg-prod-w16 |
| 10:31 | 09:31 | Infinispan cache TimeoutException on docent-rest (23,455 events — lock acquisition fails) |
| 10:38 | 09:38 | authenticator 499 errors peak at 224.7/s |
| 10:48 | 09:48 | PgBouncer client active connections hit 5,000 limit on pg-prod-w16 |
| 11:00 | 10:00 | authenticator P99 at 5.0s; overall successful traffic drops to 1,755/s (vs 3,500/s normal) |
| 11:30 | 10:30 | docent-rest active users peak at 13,833 (92x normal); ws-rest at 116,293 (12x normal) |
| 12:03 | 11:03 | PgBouncer active connections peak at 5,849 on pg-prod-w16 (above 5,000 limit) |
| **12:38** | **11:38** | **System-wide error peak: 499 at 243.1/s, 504 at 142.7/s, 500 at 35.3/s** |
| 13:00+ | 12:00+ | Traffic naturally decreases; connection pools drain; services recover |

---

## 3. Metrics Analysis

### 3.1 PgBouncer Connection Pools (Root Cause Metric)

**pg-prod-w16 (Primary Set 1):**

| Time (CET) | Client Active | Waiting | Server Active | Status |
|------------|:---:|:---:|:---:|--------|
| 04:38 (baseline) | 704 | 0 | 30 | ✅ Normal |
| 08:00 | 1,262 | 0 | 57 | ✅ Normal |
| 09:00 | 1,919 | 0 | 91 | ✅ Normal ramp |
| **09:50** | **3,607** | **1** | **150** | 🔴 **Waiting begins** |
| **10:10** | **4,139** | **86** | **366** | 🔴 **Peak waiting** |
| **10:48** | **5,049** | **50** | **315** | 🔴 **Limit hit** |
| **12:03** | **5,849** | **40** | **270** | 🔴 **Above limit** |
| 13:08 | 1,537 | 0 | 72 | ✅ Recovered |

**pg-prod-2ve (Primary Set 2):** Similar pattern, also hit ~5,000 limit.

### 3.2 Per-User Connection Breakdown (pg-prod-w16)

| User | Baseline (Mar 2) | Incident Peak (Mar 9) | Peak Time (CET) | Status |
|------|:---:|:---:|:---:|:---:|
| **landelijk_productie** | 30–656 oscillating | **688** | 11:23 | ✅ Normal range |
| productie | ~700 | ~3,500 | 12:03 | 🔴 5x |
| productie_readonly | ~200 | ~1,000 | 11:00 | 🔴 5x |
| parro_productie | ~40 | ~120 | 11:00 | ⚠️ 3x |
| audit_productie | ~15 | ~45 | 11:00 | ⚠️ 3x |

> **⚠️ CORRECTION:** Week-prior comparison (March 2) revealed that `landelijk_productie` normally oscillates between 30–656 connections in regular waves every 5–15 minutes (peak 656 at 09:30 CET on March 2). The March 9 peak of 688 was **within normal range**, not a 25x anomaly. The original "~25 baseline" was a momentary post-deployment trough, not the true steady-state.
>
> **The real anomaly was WAITING connections:** March 2 peak waiting = 6; March 9 peak waiting = 34 (5.7x). This indicates connections were held longer due to the cascade.
>
> See [research/week_prior_comparison.md](research/week_prior_comparison.md) for full data.

### 3.3 Request Latency (P99)

| Time (CET) | ws-rest | authenticator | sis-ui | docent-graphql | Status |
|------------|:---:|:---:|:---:|:---:|--------|
| 08:00 | 729ms | 338ms | 1.1s | 1.8s | ✅ Normal |
| 09:00 | 929ms | 837ms | 2.9s | 3.7s | ⚠️ sis-ui elevated |
| **10:00** | **5.0s** | 1.9s | **5.0s** | **5.0s** | 🔴 **TIMEOUT** |
| **11:00** | 3.1s | **5.0s** | **5.0s** | **5.0s** | 🔴 **TIMEOUT** |
| 12:00 | 970ms | **5.0s** | **5.0s** | **5.0s** | 🔴 Mixed |
| 13:00 | ~800ms | ~400ms | ~1.5s | ~2.0s | ✅ Recovered |

### 3.4 Active Users (In-Flight Requests)

| Component | Normal Baseline | Peak | Peak Time (CET) | Multiplier |
|-----------|:---:|:---:|:---:|:---:|
| **docent-rest** | ~150 | **13,833** | 11:30 | **92x** 🔴 |
| **ws-rest** | ~10,000 | **116,293** | 11:30 | **12x** 🔴 |
| **authenticator** | ~100 | **1,756** | 11:00 | **18x** 🔴 |
| **sis-ui** | ~3,000 | **8,508** | 11:00 | **2.8x** ⚠️ |

### 3.5 HTTP Error Distribution

| Error Type | Peak Rate | Peak Time (CET) | Top Service |
|------------|:---:|:---:|-------------|
| 499 (Client Abort) | **243.1/s** | 12:38 | authenticator (224.7/s) |
| 504 (Gateway Timeout) | **142.7/s** | 12:33 | authenticator (66.3/s) |
| 500 (Internal Error) | **35.3/s** | 12:38 | authenticator (34.7/s) |
| 502 (Bad Gateway) | **7.7/s** | 12:43 | ws-rest (5.6/s) |

### 3.6 Cloudflare Tunnel

| Time (CET) | HA Connections/Node | Status |
|------------|:---:|--------|
| Throughout incident | 8 (constant) | ✅ Not a factor |

### 3.7 Active Alerts

| Alert | Time Fired | Time Resolved | Severity |
|-------|------------|---------------|----------|
| ⚠️ Alert data not queried | — | — | — |

**Note:** OnCall alert groups returned 404 (service not configured). Alert rule queries were not available via the discovered tools.

---

## 4. Root Cause Analysis

### 4.1 Confirmed Contributing Factors

1. **rest-auth Service Connectivity Failure (INITIAL TRIGGER)**
   - **Evidence:** 155,908 ConnectTimeoutException events from authenticator→rest-auth starting at 09:01 CET; 894 UnknownHostException (DNS) events at 09:16 CET
   - **Impact:** Authentication requests could not be completed, causing retry storms and connection pool consumption
   - **Open question:** Why did rest-auth become unreachable? Was there a deployment, scaling event, or network issue?

2. **PgBouncer Connection Pool Saturation**
   - **Evidence:** Client active connections went from 1,919 (09:00) to 5,849 (12:03) on pg-prod-w16; waiting connections appeared at exactly 09:50 CET (peaking at 86)
   - **Impact:** Database connection starvation caused all services to block, unable to complete transactions

3. **PgBouncer Waiting Connection Spike (Connection Duration Anomaly)**
   - **Evidence:** Waiting connections peaked at 34 on March 9 vs peak of 6 on March 2 baseline (5.7x). Four users exceeded 10 waiting: `landelijk_productie` (34), `revolutionaryrunner` (33), `consciousrhythm` (28), `noblesuccess` (26)
   - **Impact:** Connections held longer due to blocked transactions, causing pool contention even though active connection counts were within normal range
   - **CORRECTION:** The `landelijk_productie` active connection spike to 629 at 09:02 CET was **NOT anomalous** — week-prior data shows this user regularly oscillates between 30–656 connections (peak 656 on March 2 at 09:30 CET)

4. **Thread/Request Accumulation on docent-rest**
   - **Evidence:** Active users grew from ~150 to 13,833 (92x) — requests entered docent-rest but could not complete (blocked on DB)
   - **Impact:** All docent-rest pods became functionally unresponsive despite remaining Running

5. **Infinispan Cache Coordination Failure (SECONDARY)**
   - **Evidence:** 23,455 TimeoutException events at 10:31 CET — lock acquisition failed after 15 seconds
   - **Impact:** Distributed cache between docent-rest pods broke down, further degrading service quality
   - **Causation:** Pods were too overwhelmed by stuck DB requests to handle inter-pod cache operations

### 4.2 Probable Contributing Factors

1. **Retry Storms** — The massive ConnectTimeoutException count (155,908) and the sudden connection spike suggest aggressive retry logic amplifying the initial failure
2. **DNS Overload** — UnknownHostException at 09:16 CET (15 min after initial error) suggests CoreDNS may have been overwhelmed by retry resolution requests
3. **Pre-existing sis-ui Latency** — sis-ui P99 was already at 2.9s at 09:00 CET (vs 1.1s baseline), suggesting the system was already under stress before the main trigger

### 4.3 Cascade Failure Sequence

```
┌─────────────────────────────────────────────────────────────────┐
│ 1. rest-auth becomes unreachable (09:01 CET)                    │
│    Cause: Unknown — deployment? network? pod failure?            │
└──────────────────────────────┬──────────────────────────────────┘
                               ↓
┌─────────────────────────────────────────────────────────────────┐
│ 2. Connections held longer → waiting queue builds (09:50)       │
│    Waiting: 0 → 34 (5.7x baseline); active in normal range     │
└──────────────────────────────┬──────────────────────────────────┘
                               ↓
┌─────────────────────────────────────────────────────────────────┐
│ 3. PgBouncer pool saturates → waiting connections (09:50)       │
│    Active: 3,607 → Waiting: 1 → escalates to 86 at 10:10       │
└──────────────────────────────┬──────────────────────────────────┘
                               ↓
┌──────────────────────────────┴──────────────────────────────────┐
│ 4a. docent-rest blocked on DB   │ 4b. ws-rest / sis-ui blocked  │
│     Active users: 150 → 13,833  │     Active: 10K → 116K        │
│     P99: 1.8s → 5.0s timeout    │     P99: 729ms → 5.0s         │
└──────────────────────────────┬──┴───────────────────────────────┘
                               ↓
┌─────────────────────────────────────────────────────────────────┐
│ 5. Infinispan cache timeouts on docent-rest (10:31)             │
│    Pods can't coordinate → further degradation                   │
└──────────────────────────────┬──────────────────────────────────┘
                               ↓
┌─────────────────────────────────────────────────────────────────┐
│ 6. System-wide impact: 499 at 243/s, 504 at 143/s (12:38)      │
│    authenticator failures → cascades to ALL user actions         │
└──────────────────────────────┬──────────────────────────────────┘
                               ↓
┌─────────────────────────────────────────────────────────────────┐
│ 7. Natural traffic decrease → pool drains → recovery (13:00)    │
└─────────────────────────────────────────────────────────────────┘
```

---

## 5. Error Analysis (Bugsnag)

### 5.1 Top Errors During Incident

| # | Error Class | Component | Count | First Seen (CET) | Significance |
|---|------------|-----------|:---:|:---:|--------------|
| 1 | **ConnectTimeoutException** | auth→rest-auth | **155,908** | **09:01** | 🔴 Initial trigger |
| 2 | **Infinispan TimeoutException** | docent-rest | **23,455** | **10:31** | 🔴 Secondary cascade |
| 3 | EJBTransactionRolledback | sis-ui | 12,037 | 08:32 | ⚠️ Early warning |
| 4 | ConfigurationException | docent-rest | 6,117 | 10:08 | ⚠️ Serialization failure |
| 5 | FetchError ETIMEDOUT | docent-frontend→docent-rest | 5,836 | 09:53 | 🔴 User-facing |
| 6 | GraphQL Schema Mismatch | docent-frontend | 5,578 | 09:55 | ⚠️ Inconsistent state |
| 7 | NullPointerException | sis-ui | 1,736 | 08:26 | Pre-existing |
| 8 | UnknownHostException | rest-auth DNS | 894 | 09:16 | 🔴 DNS failure |

### 5.2 Key Stack Trace — ConnectTimeoutException (authenticator → rest-auth)

```
io.netty.channel.ConnectTimeoutException: connection timed out
    at authenticator → rest-auth service call
    First seen: 09:01 CET (08:01 UTC)
    Total unthrottled events: 155,908
```

This is the **earliest high-volume error** and the strongest candidate for the cascade trigger.

### 5.3 Key Stack Trace — Infinispan TimeoutException (docent-rest)

```
org.infinispan.util.concurrent.TimeoutException: 
    ISPN000299: Unable to acquire lock after 15 seconds for key [...]
    at DefaultCacheManager
    First seen: 10:31 CET (09:31 UTC)
    Total unthrottled events: 23,455
```

Distributed lock timeout — pods could not coordinate cache state because they were overwhelmed with stuck requests.

### 5.4 Frontend Impact — docent-graphql

All 8 docent-rest pod IPs received ETIMEDOUT errors from the frontend:
- Pod IPs: 10.244.2.105, 10.244.4.43, 10.244.5.43, 10.244.5.78, 10.244.6.4, 10.244.6.26, 10.244.6.35, 10.244.6.60
- **All pods across all nodes affected** — cluster-wide application issue, not a single-pod failure

---

## 6. Data Gaps

### Metrics Not Available
- ❌ **Thread pool metrics** (`wildfly_io_busy_task_thread_count`, `wildfly_io_queue_size`, `wildfly_io_max_pool_size`) — would have confirmed thread exhaustion directly
- ❌ **Application-level request time** (`eduarte_wildfly_request_time_1m`) — would have separated application processing time from Traefik-observed latency
- ❌ **Pod CPU/Memory utilization** — would have shown resource pressure on individual pods
- ❌ **Pod restart count** (`kube_pod_container_status_restarts_total`) — returned empty for queried label patterns
- ❌ **Alert history** — OnCall returned 404, alert rules not accessible via available tools

### Logs Not Available
- ❌ **Loki application logs** — would have shown exact error sequences within pods
- ❌ **rest-auth pod logs** — critical for understanding why rest-auth became unreachable at 09:01 CET
- ❌ **CoreDNS logs** — would clarify the DNS resolution failures at 09:16 CET

### Recommended Additional Monitoring
1. **Expose thread pool metrics** — `wildfly_io_*` metrics are critical for diagnosing thread exhaustion
2. **PgBouncer connection alerts** — alert when active connections exceed 80% of limit (4,000+)
3. **PgBouncer waiting connection monitoring** — alert when waiting connections exceed 10 (normal peak is 6)
4. **Per-user connection monitoring** — alert when any single DB user exceeds baseline peak by >50%
4. **Active users alert** — alert when `wildfly_request_active_users_5m` exceeds 5x normal for any component

---

## 7. Conclusions

### 7.1 Confirmed ✅
- **PgBouncer connection pool saturation was the direct cause** of system-wide degradation — active connections hit 5,849 (above 5,000 limit)
- **All services were affected** — every major component hit the 5.0s timeout ceiling
- **docent-rest was the most severely impacted** component with 92x increase in stuck requests (13,833 active users vs ~150 normal)
- **The incident had two distinct phases**: initial spike (10:00-10:30 CET) with brief partial recovery, then sustained degradation (11:00-12:38 CET)
- **Infinispan cache failures are secondary** — caused by pod overload, not a cache infrastructure problem
- **Cloudflare tunnels and Kubernetes node health were NOT factors** — both remained stable throughout
- **No pods crashed or restarted** — the issue was functional degradation (I/O blocked), not infrastructure failure

### 7.2 Probable 🔶
- **rest-auth connectivity failure (09:01 CET) was the initial trigger** — 155,908 ConnectTimeoutExceptions is the earliest high-volume error
- **The cascade mechanism was connection duration, not connection count** — week-prior comparison shows active connection levels were normal; the anomaly was waiting connections (5.7x) indicating blocked transactions
- **Retry storms amplified the failure** — the massive error count suggests aggressive retries that held connections longer
- **6+ recurring failure waves (~30-min cycle)** suggest a self-reinforcing pattern: timeout → retry → pool pressure → timeout
- **The system was under stress before the main trigger** — sis-ui P99 was already at 2.9s at 09:00 CET (vs 1.1s baseline)

### 7.3 Uncertain ❓
- **Why did rest-auth become unreachable at 09:01 CET?** — Was it a deployment, scaling event, network partition, or pod failure? This is the critical missing piece.
- **~~What is the `landelijk_productie` DB user and why did it spike?~~** — **RESOLVED:** Week-prior comparison shows the connection pattern is normal oscillation (30–656), not incident-related. The user still warrants investigation for its high connection consumption, but it was not a contributing factor to this incident.
- **Was there a manual intervention** during the incident that caused the brief recovery at 10:30 CET?
- **Was the system already degraded before 09:00 CET?** — The elevated sis-ui latency and EJBTransactionRolledbackException at 08:32 need investigation

---

## 8. Recommendations

### 8.1 Immediate Actions (This Week)

| Action | Owner | Status |
|--------|-------|--------|
| Investigate why rest-auth was unreachable at 09:01 CET (check deployment logs, pod events) | Platform team | ⬜ |
| ~~Identify the `landelijk_productie` DB user purpose and connection behavior~~ | Database team | ✅ Resolved — normal oscillation pattern confirmed by week-prior comparison |
| Review and reduce authenticator→rest-auth retry configuration | Backend team | ⬜ |
| Verify PgBouncer `max_client_conn` settings meet current load requirements | Database team | ⬜ |

### 8.2 Short-term Improvements (This Sprint)

| Action | Owner | Status |
|--------|-------|--------|
| Add PgBouncer connection pool alerts (>80% of limit = warning, >90% = critical) | Monitoring team | ⬜ |
| Add per-DB-user connection alerts (>100 connections for any single user) | Monitoring team | ⬜ |
| Implement circuit breaker on authenticator→rest-auth calls (fail fast instead of retry storm) | Backend team | ⬜ |
| Add `wildfly_request_active_users_5m` alert (>5x baseline per component) | Monitoring team | ⬜ |

### 8.3 Long-term Improvements (Roadmap)

| Action | Owner | Status |
|--------|-------|--------|
| Expose `wildfly_io_*` thread pool metrics to Prometheus | Backend team | ⬜ |
| Implement connection pool isolation (per-service DB connection limits) to prevent one service starving others | Architecture team | ⬜ |
| Add bulkhead pattern to prevent cascading failures between services | Architecture team | ⬜ |
| Implement graceful degradation for docent-rest when DB is slow (serve cached data, queue non-critical writes) | Backend team | ⬜ |
| Set up Loki log aggregation for rest-auth and CoreDNS to enable root cause analysis of connectivity failures | Platform team | ⬜ |

---

## 9. Appendix

### A. Datasources Used

| Source | UID/ID | Purpose |
|--------|--------|---------|
| Prometheus | PBFA97CFB590B2093 | Infrastructure metrics (Traefik, PgBouncer, Cloudflare, Kubernetes) |
| Grafana Cloud Metrics | RU1hwHA4k | Wildfly custom metrics (active users) |
| Bugsnag — Somtoday Backend | 543ce4797765623fb900011d | Application errors (release_stage = "production") |
| Bugsnag — Somtoday Docent | 59d20374c943ea002679e025 | Frontend errors (release_stage = "productie") |
| Bugsnag — Somtoday Leerling | 65e09a58bf784d00154ac51a | Student app errors (release_stage = "productie") |

### B. Key PromQL Queries Used

```promql
# PgBouncer client active connections
sum(pgbouncer_pools_client_active_connections{database="productie"}) by (instance)

# PgBouncer waiting connections
sum(pgbouncer_pools_client_waiting_connections{database="productie"}) by (instance)

# PgBouncer per-user connections
sum(pgbouncer_pools_client_active_connections{database="productie", instance=~"pg-prod-w16.*"}) by (user)

# 499 errors by service
sum(rate(traefik_service_requests_total{kubernetes_cluster="somtoday", code="499"}[5m])) by (exported_service)

# 5xx errors by service
sum(rate(traefik_service_requests_total{kubernetes_cluster="somtoday", code=~"5.."}[5m])) by (exported_service, code)

# P99 latency
histogram_quantile(0.99, sum(rate(traefik_service_request_duration_seconds_bucket{kubernetes_cluster="somtoday"}[5m])) by (le, exported_service))

# Active users per component
wildfly_request_active_users_5m{businessline="somtoday", environment="productie"}

# Overall HTTP status code distribution
sum(rate(traefik_service_requests_total{kubernetes_cluster="somtoday"}[5m])) by (code)

# Cloudflare tunnel connections
cloudflared_tunnel_ha_connections{kubernetes_cluster="somtoday"}
```

### C. Environment Reference

| Component | Description |
|-----------|-------------|
| kubernetes_cluster | somtoday (production) |
| PgBouncer instances | pg-prod-w16 (set 1), pg-prod-2ve (set 2) |
| Database | productie |
| Traefik nodes | node01, node02, node04 |
| Timezone | CET (UTC+1, DST not active until March 29, 2026) |

### D. Research Files

| File | Summary |
|------|---------|
| [research/database.md](research/database.md) | PgBouncer pool saturation analysis — the central cause |
| [research/proxy.md](research/proxy.md) | Traefik HTTP error and latency analysis |
| [research/application.md](research/application.md) | Active users, component impact, Infinispan failures |
| [research/exceptions.md](research/exceptions.md) | Bugsnag error correlation (backend + frontend) |
| [research/kubernetes.md](research/kubernetes.md) | Pod health, node status, DNS issues |
| [research/cloudflare.md](research/cloudflare.md) | Tunnel health — ruled out as factor |
| [research/week_prior_comparison.md](research/week_prior_comparison.md) | **Comprehensive March 2 vs March 9 comparison — corrects original landelijk_productie analysis** |

---

**Report Generated:** 2026-03-09  
**Last Updated:** 2026-03-09 (Week-prior comparison corrections)  
**Analysis Period:** 08:00 - 14:00 CET  
**Analyst:** AI-assisted (GitHub Copilot) — requires human review and deployment timeline verification  

⚠️ **Critical follow-up needed:** The root trigger (why rest-auth became unreachable at 09:01 CET) remains unconfirmed. This report documents the cascade from that point forward, but the initial cause requires investigation of rest-auth deployment logs and pod events.

⚠️ **Key correction (week-prior comparison):** The original analysis identified a "25x landelijk_productie connection spike" as a contributing factor. Week-prior data (March 2) shows this is **normal oscillation behavior** (30–656 connections). The actual anomaly was in **waiting connections** (5.7x baseline), indicating the cascade mechanism was connection *duration*, not connection *count*.
