# 📊 Week-Prior Comparison: March 9 vs March 2, 2026

**Incident Day:** Monday, March 9, 2026 (v16.8.0-21, deployed 08:43 CET)
**Baseline Day:** Monday, March 2, 2026 (v16.7.0-25-jee10, stable)
**Comparison Window:** 08:00 - 13:00 CET (07:00 - 12:00 UTC)

---

## 1. PgBouncer Active Connections — `landelijk_productie` (pg-prod-w16)

### ⚠️ CRITICAL CORRECTION: The `landelijk_productie` spike was NORMAL behavior

The original postmortem described `landelijk_productie` connections spiking from "~25 baseline" to 629 as a "25x anomaly." **Week-prior data proves this is normal:**

| Metric | March 2 (Baseline) | March 9 (Incident) | Delta |
|--------|:---:|:---:|:---:|
| **Peak active connections** | **656** | **688** | +5% ✅ Normal |
| Pattern | Oscillating 30-656 in waves | Oscillating 31-629 in waves | Same pattern |
| Observed wave frequency | Every 5-15 minutes | Every 5-15 minutes | Same |
| **Peak WAITING connections** | **6** | **34** | **+467%** 🔴 |

### March 2 (baseline) — landelijk_productie active connections on pg-prod-w16

| Time (CET) | Active | Notes |
|------------|:---:|-------|
| 08:50 | 283 | Mid-wave |
| 08:56 | 47 | Trough |
| 09:02 | 280 | Wave start |
| 09:09 | 469 | Wave peak |
| 09:10 | 66 | Trough |
| 09:16-09:25 | 111-289 | Wave |
| **09:30** | **656** | **Day peak** |
| 09:35 | 50 | Trough |
| 09:53 | 580 | Wave |
| 10:00 | 293 | Sustaining |

### March 9 (incident) — landelijk_productie active connections on pg-prod-w16

| Time (CET) | Active | Notes |
|------------|:---:|-------|
| 08:50 | 31 | Low (post-deployment trough) |
| 08:54 | 99 | Rising |
| 08:55 | 271 | Wave start (normal) |
| 09:02 | **629** | **Wave peak (comparable to Mar 2's 656)** |
| 09:06 | 42 | Trough |
| 09:08-09:12 | 270-304 | Wave |
| 09:13 | 60 | Trough |
| 09:14-09:39 | 24-44 | Calm (normal) |
| 09:40-10:00 | 97-366 | Third wave starting |
| **11:23** | **688** | **Day peak (only 5% above Mar 2)** |

### Key Insight

The 31→629 spike on March 9 looks dramatic in isolation but is **within the normal oscillation range** seen on March 2. The "~25 baseline" used in the original analysis was actually a post-deployment momentary trough, not the true baseline.

**However:** The WAITING connections tell a different story. March 2 had peak waiting of only 6 (at 09:08 CET). March 9 reached 34 waiting (at 09:52 CET). This 467% increase indicates that while the CONNECTION COUNT was normal, something was making connections SLOWER to release — likely the cascade failure causing long-running transactions.

---

## 2. HTTP Error Rates (All Services Combined)

| Error Code | March 2 Peak | March 9 Peak | Multiplier | Assessment |
|:---:|:---:|:---:|:---:|:---:|
| **499** | 3.2 req/s | **272.8 req/s** | **85x** | 🔴 Critical |
| **500** | 0.1 req/s | **35.3 req/s** | **353x** | 🔴 Critical |
| **502** | 0.0 req/s | **6.6 req/s** | **∞** | 🔴 Critical |
| **504** | 0.0 req/s | **67.4 req/s** | **∞** | 🔴 Critical |

### March 9 — 499 Error Wave Pattern (system-wide)

The incident was NOT a single spike. It consisted of **6+ distinct recurring waves** from 09:51 to well past 13:00 CET:

| Wave | Start (CET) | Peak (CET) | Peak Rate | Duration |
|:---:|:---:|:---:|:---:|:---:|
| 1 | 09:51 | 09:57 | 160.8 req/s | ~11 min |
| 2 | 10:04 | 10:10 | 193.6 req/s | ~11 min |
| 3 | 10:33 | 10:41 | 258.6 req/s | ~18 min |
| 4 | 10:52 | 11:02 | 272.8 req/s | ~20 min |
| 5 | 11:28 | 11:37 | 244.8 req/s | ~21 min |
| 6 | 11:52 | 12:36 | 245.4 req/s | ~44 min (sustained) |

### March 9 — ws-rest HTTP Error Breakdown

| Error Code | Peak Rate | Peak Time | Notes |
|:---:|:---:|:---:|-------|
| 499 | 163.7 req/s | 10:10 CET | Client disconnects (timeouts) |
| 500 | 11.0 req/s | 11:07 CET | Internal server errors |
| 502 | 6.6 req/s | 10:10 CET | Bad gateway (upstream failures) |
| 504 | 67.4 req/s | 11:39 CET | Gateway timeout |

---

## 3. Cloudflare Tunnel Throughput

| Metric | March 2 (Baseline) | March 9 (Incident) | Assessment |
|--------|:---:|:---:|:---:|
| Minimum throughput | 3,855 req/s | **785 req/s** | 🔴 **80% drop** |
| Maximum throughput | 4,768 req/s | 5,694 req/s | ✅ (recovery spikes) |
| Stability | Stable, <15% variance | **Multiple 50-80% drops** | 🔴 |

### March 9 — Cloudflare Tunnel Dip Pattern

| Time (CET) | Throughput (req/s) | Status |
|:---:|:---:|:---:|
| 09:00-10:30 | 4,500-4,900 | ✅ Normal (pre-dip) |
| **10:35** | **3,190** | ⚠️ First dip |
| **10:40** | **1,985** | 🔴 Major dip |
| 10:45 | 5,337 | ✅ Recovery |
| **11:00** | **1,933** | 🔴 Major dip |
| 11:05 | 5,036 | ✅ Recovery |
| **11:35** | **1,772** | 🔴 Major dip |
| 11:40 | 4,514 | ✅ Recovery |
| 11:55 | 2,675 | ⚠️ Dip |
| **12:25-12:55** | **785-1,363** | 🔴 **Sustained degradation** |
| 13:00 | 4,344 | ✅ Recovery |

### March 2 (baseline) — Cloudflare Tunnel

Stable throughout: 3,855-4,768 req/s with <15% variance. **No dips.**

---

## 4. ws-rest Request Throughput

| Metric | March 2 | March 9 | Assessment |
|--------|:---:|:---:|:---:|
| Steady-state (09:00-10:00 CET) | 3,100-3,500 req/s | 3,200-3,700 req/s | ✅ Comparable |
| Minimum during incident | N/A | **581 req/s** (10:25 CET) | 🔴 |
| **Dip pattern** | None | Multiple dips to 890-2,060 | 🔴 |

### March 9 — ws-rest Throughput Dips (correlated with Cloudflare & 499 waves)

| Time (CET) | Throughput | Status |
|:---:|:---:|:---:|
| 10:30 | 3,442 | ✅ Normal |
| 10:35 | 2,060 | ⚠️ Dip starts |
| 10:40 | 973 | 🔴 Major dip |
| 10:45 | 3,766 | ✅ Recovery |
| 11:00 | 985 | 🔴 Major dip |
| 11:05 | 3,639 | ✅ Recovery |
| 11:30 | 3,096 | ⚠️ |
| 11:35 | 1,772 | 🔴 Major dip |
| 11:40 | 4,514 | ✅ Recovery |
| 12:10 | 3,241 | ⚠️ Partial |
| 12:20 | 2,256 | ⚠️ |
| 12:25 | 1,032 | 🔴 Major dip |
| 12:30 | 693 | 🔴 Severe |
| 12:35 | 654 | 🔴 Severe |
| 12:40 | 581 | 🔴 **Minimum** |
| 12:50 | 315 | 🔴 Near-zero |
| 12:55 | 212 | 🔴 Near-zero |
| 13:00 | 3,142 | ✅ Recovery |

---

## 5. Active Users (Wildfly)

| Component | March 2 @ 10:00 | March 9 @ 10:00 | March 9 @ 11:00 | Assessment |
|-----------|:---:|:---:|:---:|:---:|
| **ws-rest** | 105,308 | 104,314 | **39,042** | 🔴 63% drop by 11:00 |
| **sis-ui** | 11,134 | 8,836 | 7,493 | ⚠️ 33% below baseline |
| **docent-rest** | 10,750 | 13,285 | **4,719** | 🔴 56% drop by 11:00 |
| connect-rest | 17 | 14 | 16 | ✅ Stable |
| authenticator | 3 | 3 | 2 | ✅ Stable |

**Key:** The massive ws-rest user drop from 104,314 (10:00) to 39,042 (11:00) represents ~65,000 users losing access during the incident. Docent-rest similarly dropped from 13,285 to 4,719.

---

## 6. Bugsnag Error Comparison (Backend, production, 07:00-13:00 CET)

| Error Class | March 2 Events | March 9 Events | Multiplier | Context |
|------------|:---:|:---:|:---:|-------|
| `RollbackException` | 396 | **957** | **2.4x** | rest |
| `ProcessingException` (SocketTimeout) | 39 | **859** | **22x** 🔴 | authenticator |
| `WebApplicationException` (HTTP 500) | 18 | **701** | **39x** 🔴 | authenticator |
| `OptimisticLockException` | 22 | **171** | **7.8x** 🔴 | rest |
| `EJBTransactionRolledbackException` | 64 | elevated | est. 3-5x | sis-ui |
| `Infinispan TimeoutException` | 0 | **7** | new 🔴 | rest |
| **Total error classes** | 30 | **130** | **4.3x** | — |

### New errors on March 9 (not present on March 2):
- `org.infinispan.commons.TimeoutException` — 7 events (JGroups response timeout, cache cluster issues)
- `ProcessingException` / `UnknownHostException` — 29 events (DNS failure for prod-rest-auth)

---

## 7. BO Sync Jobs Confirmation

**Status: No evidence of BO sync job execution on March 9.**

- ❌ **Loki logs:** Not available (no Loki datasource accessible; received 403 Forbidden)
- ❌ **Prometheus scheduler metrics:** No `wildfly_scheduler_*` or `job*` metrics exist on either datasource
- ✅ **Bugsnag search:** 130 errors returned for the incident window. **ZERO** contain BO-specific, BusinessObjects, landelijk-sync, or rapportage-related errors
- ✅ **Coworker confirmation:** Engineer confirmed no BO sync jobs scheduled for March 9

**Conclusion:** Circumstantial evidence strongly supports that BO sync jobs did not run. The `landelijk_productie` connection pattern matches the normal week-prior baseline, further confirming BO jobs were not the cause.

---

## 8. PgBouncer Configuration Confirmation

| Metric | March 8 | March 9 | Status |
|--------|:---:|:---:|:---:|
| `max_client_conn` (per instance × 4) | 2,500 | 2,500 | ✅ Unchanged |
| `max_user_connections` (per instance × 4) | 12 | 12 | ✅ Unchanged |

**All 8 PgBouncer instances (4 on pg-prod-w16, 4 on pg-prod-2ve) have identical configuration.**

---

## 9. Summary of Comparison

### What was NORMAL on March 9 (same as March 2):
- `landelijk_productie` connection wave pattern (30-650 oscillations)
- ws-rest and sis-ui request throughput at 09:00-10:00 CET
- Active user counts at start of incident window

### What was ANOMALOUS on March 9 (vs March 2):
| Metric | Anomaly Factor | Severity |
|--------|:---:|:---:|
| HTTP 499 errors | **85x** | 🔴 Critical |
| HTTP 500 errors | **353x** | 🔴 Critical |
| HTTP 504 errors | **∞** (none on Mar 2) | 🔴 Critical |
| SocketTimeoutException (Bugsnag) | **22x** | 🔴 Critical |
| WebApplicationException 500 (Bugsnag) | **39x** | 🔴 Critical |
| PgBouncer waiting connections | **5.7x** | 🔴 |
| Cloudflare tunnel minimum throughput | **80% drop** | 🔴 Critical |
| ws-rest active users at 11:00 | **63% drop** | 🔴 Critical |
| 499 recurring wave pattern | Not present on Mar 2 | 🔴 |

### Revised Root Cause Assessment

The `landelijk_productie` connection spike is **NOT the root cause** — it was normal batch processing. The true anomaly was:

1. **rest-auth connectivity failure** (ConnectTimeoutException, SocketTimeout, UnknownHostException) starting at 09:01 CET — the earliest anomaly and likely trigger
2. **PgBouncer connection pool saturation** — connections were held longer due to failing REST calls, creating waiting queues (34 vs baseline 6)
3. **Recurring failure waves** — the ~30-minute wave pattern (6+ waves, 09:51-13:00) suggests a self-reinforcing cascade: backend failures → connection hold → pool saturation → more failures → brief recovery → repeat

## Queries Used

```promql
# Active connections by user (both hosts, both days)
sum(pgbouncer_pools_client_active_connections{database="productie", instance=~"pg-prod-w16.*"}) by (user)
sum(pgbouncer_pools_client_active_connections{database="productie", instance=~"pg-prod-2ve.*"}) by (user)

# Waiting connections
sum(pgbouncer_pools_client_waiting_connections{database="productie", instance=~"pg-prod-w16.*"}) by (user)

# Error rates by code
sum(rate(traefik_service_requests_total{kubernetes_cluster="somtoday", code=~"499|5.."}[5m])) by (code)

# ws-rest errors by code
sum(rate(traefik_service_requests_total{kubernetes_cluster="somtoday", exported_service=~".*-api-ws-rest-.*"}[5m])) by (code)

# Cloudflare tunnel throughput
sum(rate(cloudflared_tunnel_total_requests{kubernetes_cluster="somtoday"}[5m]))

# ws-rest throughput
sum(rate(traefik_service_requests_total{kubernetes_cluster="somtoday", exported_service=~".*-api-ws-rest-.*"}[5m])) by (exported_service)

# Active users
wildfly_request_active_users_5m{businessline="somtoday", environment="productie"}

# Bugsnag: errors in time window for backend project
# Project: 543ce4797765623fb900011d, filter: app.release_stage=production, event.since/before
```
