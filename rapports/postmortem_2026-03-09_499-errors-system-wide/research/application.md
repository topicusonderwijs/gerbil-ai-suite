# 🚀 Application Research: System-wide 499 Errors / Connection Pool Saturation

**Investigation Time Window:** 08:00 - 14:00 CET (07:00 - 13:00 UTC)
**Components:** docent-rest, docent-graphql, ws-rest, sis-ui, authenticator, rest-auth
**Datasources:** Prometheus (PBFA97CFB590B2093), Grafana Cloud Metrics (RU1hwHA4k)

## Active Users (5-minute window)

Active users metric (`wildfly_request_active_users_5m`) tracks in-flight requests. Abnormally high values indicate requests that are NOT completing — they are stuck waiting for resources (DB connections, locks, downstream services).

### docent-rest (MAIN CULPRIT)

| Time (CET) | Active Users | Status | Interpretation |
|------------|:---:|--------|------------|
| 08:00 | 147 | ✅ Normal baseline | |
| 09:00 | 498 | ⚠️ Elevated | Growing request backlog |
| **09:30** | **3,371** | 🔴 Critical | Rapid accumulation — requests stuck |
| **10:00** | **13,577** | 🔴 **EXTREME** | Requests piling up, not completing |
| **10:30** | **12,949** | 🔴 Extreme | Sustained overload |
| 11:00 | 4,719 | 🔴 High | Partial drain or pod restart? |
| **11:30** | **13,833** | 🔴 **PEAK** | Second surge, back to extreme |
| 12:00 | 1,687 | ⚠️ Declining | Recovery starting |
| 13:00 | 109 | ✅ Normal | Recovered |

**Analysis:** docent-rest accumulated up to **13,833 active "users"** (stuck in-flight requests) — compared to a normal baseline of ~100-200. This is a **70x increase**. Requests entered docent-rest but could not complete, likely because they were blocked waiting for database connections.

### ws-rest

| Time (CET) | Active Users | Status | Interpretation |
|------------|:---:|--------|------------|
| 08:00 | 3,556 | ✅ Normal baseline | |
| 09:00 | 11,283 | ✅ Morning ramp-up | |
| **10:00** | **106,786** | 🔴 **EXTREME** | 10x normal peak |
| 11:00 | 39,042 | 🔴 High | Partial recovery |
| **11:30** | **116,293** | 🔴 **PEAK** | Worst point |
| 12:00 | 29,753 | 🔴 High | |
| 13:00 | 5,199 | ✅ Normal | Recovered |

**Analysis:** ws-rest peaked at **116,293 active users** — indicating massive request queueing. Normal peak traffic is ~10,000-15,000.

### authenticator

| Time (CET) | Active Users | Status | Interpretation |
|------------|:---:|--------|------------|
| 08:00 | 35 | ✅ Normal | |
| 09:00 | 116 | ✅ Normal | |
| **10:00** | **889** | 🔴 High | 8x normal |
| **11:00** | **1,756** | 🔴 Critical | Accumulating |
| 12:00 | 1,020 | 🔴 High | Still elevated |
| 13:00 | 45 | ✅ Normal | Recovered |

### sis-ui

| Time (CET) | Active Users | Status | Interpretation |
|------------|:---:|--------|------------|
| 08:00 | 1,116 | ✅ Normal | |
| 09:00 | 3,362 | ✅ Morning peak | |
| **10:00** | **8,327** | 🔴 Elevated | 2.5x normal |
| **11:00** | **8,508** | 🔴 Elevated | |
| 12:00 | 3,499 | ✅ Normal | Recovered |

### Component Comparison (Peak Active Users)

| Component | Normal Baseline | Incident Peak | Multiplier |
|-----------|:---:|:---:|:---:|
| **docent-rest** | ~150 | **13,833** | **92x** 🔴 |
| **ws-rest** | ~10,000 | **116,293** | **12x** 🔴 |
| **authenticator** | ~100 | **1,756** | **18x** 🔴 |
| **sis-ui** | ~3,000 | **8,508** | **2.8x** ⚠️ |

## Infinispan Cache Issues

At **10:31 CET** (09:31 UTC), Infinispan distributed cache operations started timing out between docent-rest pods:

**Error:** `org.infinispan.util.concurrent.TimeoutException: ISPN000299: Unable to acquire lock after 15 seconds`

- **23,455 occurrences** in Bugsnag (unthrottled)
- Affected `DefaultCacheManager` on docent-rest pods
- Lock timeouts indicate pods were too busy to respond to cache operations
- This is a **secondary effect** — pods were overwhelmed by stuck DB requests and couldn't handle inter-node cache coordination

## Thread Pool Metrics

⚠️ **Data Unavailable:** `wildfly_io_busy_task_thread_count`, `wildfly_io_queue_size`, and `wildfly_io_max_pool_size` queries returned **empty results** on both Prometheus datasources. Thread pool utilization could not be directly measured.

However, the massive accumulation of active users (13,833 on docent-rest, 116,293 on ws-rest) strongly implies **thread pool exhaustion** — worker threads were all blocked waiting for database connections, with new requests queueing behind them.

## Application-Level Latency (Wildfly Custom Metrics)

⚠️ **Data Unavailable:** `eduarte_wildfly_request_time_1m{environment_type="production"}` returned **empty results** on the secondary datasource (RU1hwHA4k). Application-internal processing time could not be measured separately from Traefik-observed latency.

## Cascade Failure Sequence (Application Layer)

```
09:01  authenticator fails to connect to rest-auth (ConnectTimeoutException)
  ↓
09:02  landelijk_productie user spikes to 629 DB connections (retry storm?)
  ↓
09:30  docent-rest active users at 3,371 (requests queueing)
  ↓
09:50  PgBouncer waiting connections appear → DB connection starvation
  ↓
10:00  ws-rest and sis-ui hit 5.0s timeouts → system-wide impact
  ↓
10:31  Infinispan cache timeouts → docent-rest inter-node communication fails
  ↓
10:38  authenticator 499 errors peak at 224.7/s → auth cascade
  ↓
11:30  ws-rest peaks at 116K active users, docent-rest at 13.8K
  ↓
12:38  System-wide error peak: 499 at 243/s, 504 at 143/s
  ↓
13:00  Natural traffic decrease allows system to drain and recover
```

## Queries Used

```promql
# Active users per component
wildfly_request_active_users_5m{businessline="somtoday", environment="productie"}

# Thread pool utilization (RETURNED EMPTY)
(wildfly_io_busy_task_thread_count{kubernetes_cluster="somtoday", environment="productie"} + wildfly_io_queue_size) / wildfly_io_max_pool_size * 100

# Application-level request time (RETURNED EMPTY)
eduarte_wildfly_request_time_1m{environment_type="production", component="docent-rest"}
```

## Key Observations

- 🔴 **docent-rest was the most severely affected component** with a 92x increase in active users — requests entered but could not complete
- 🔴 **ws-rest accumulated 116,293 active users** — the highest absolute number, but a lower relative increase (12x)
- 🔴 **authenticator cascaded the failure to all services** — when auth is slow/down, every user action that requires authentication is affected
- 🔴 **Infinispan cache timeouts at 10:31 CET** are a secondary effect — pods were too busy handling stuck requests to coordinate distributed caches
- ⚠️ Thread pool and application-level request time metrics were **unavailable** — this is a monitoring gap
- The **two-phase pattern** (spike at 10:00, partial recovery at 10:30, second spike at 11:00-12:38) suggests either:
  - Intervention attempt that briefly helped but didn't address root cause
  - Traffic pattern variation (morning peak had two waves)
  - Connection pool temporarily draining before being overwhelmed again
