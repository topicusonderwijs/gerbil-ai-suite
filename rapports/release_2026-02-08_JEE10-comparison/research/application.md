# 🚀 Application Research: JEE10 Post-Release Weekend Comparison

**Comparison Window:** Feb 7-8, 2026 (Sat-Sun) vs Jan 24-25, 2026 (Sat-Sun)
**Context:** JEE10 first deployed Jan 31, rolled back to JEE8 on Feb 2, **re-deployed Feb 6 17:00 CET**. This is ~40 hours into the second JEE10 deployment.
**Previous Weekend (Jan 31-Feb 1):** Showed critical sis-ui P99 regression (+167%). Rolled back to JEE8 on Monday Feb 2.

---

## Response Times (P99) — Saturday 12:00 CET

| Component | Jan 24 (JEE8) | Feb 7 (JEE10) | Delta | Status |
|-----------|--------------|---------------|-------|--------|
| **sis-ui** | 1.110s | 1.054s | **-5.1%** | ✅ Improved |
| **ws-rest** | 0.743s | 0.807s | +8.7% | ⚠️ Slight degradation |
| **authenticator** | 0.167s | 0.321s | **+92.2%** | 🔴 Regression |
| **connect-rest** | NaN | 1.182s | N/A (no baseline) | ❓ |

### Key Finding: sis-ui P99 Recovery

The **critical 167% sis-ui P99 regression** observed during the first JEE10 weekend (Jan 31) has **fully recovered** on Feb 7. Saturday P99 is now actually 5% better than the JEE8 baseline.

---

## sis-ui Percentile Breakdown (Saturday 12:00 CET)

| Percentile | Jan 24 (JEE8) | Feb 7 (JEE10) | Delta | Status |
|------------|--------------|---------------|-------|--------|
| **P50 (median)** | 58.6ms | 56.1ms | -4.2% | ✅ Improved |
| **P95** | 586ms | 250ms | **-57.3%** | ✅ Major improvement |
| **P99** | 1.110s | 1.054s | -5.1% | ✅ Improved |

**Critical Insight:** Not only has P99 recovered, but **P95 has dramatically improved by 57%**. This suggests that the JEE10 platform now handles the 95th percentile workload significantly better than JEE8 did.

---

## sis-ui P99 Timeline — Multi-Sample Comparison

| Time (CET) | Jan 24/25 (JEE8) | Feb 7/8 (JEE10) | Delta | Status |
|------------|------------------|-----------------|-------|--------|
| **Sat 10:00** | 1.107s | 1.074s | -3.0% | ✅ Normal |
| **Sat 12:00** | 1.110s | 1.054s | -5.1% | ✅ Improved |
| **Sat 14:00** | 1.145s | 1.068s | -6.7% | ✅ Improved |
| **Sun 08:00** | 1.076s | 0.268s | -75.1% | ✅ Very low |
| **Sun 10:00** | 1.124s | **4.126s** | **+267%** | 🔴 Spike |
| **Sun 11:00** | — | **3.727s** | — | 🔴 **Sustained** |
| **Sun 12:00** | 1.172s | *(no data yet)* | — | — |

### 🔴 Post-Deployment Warm-Up Pattern (Feb 6 Evening)

The JEE10 re-deployment at 17:00 CET on Feb 6 shows a clear warm-up pattern:

| Time (CET) | sis-ui P99 | Auth P99 | Traffic (req/s) | Context |
|------------|-----------|----------|-----------------|---------||
| **Fri 18:00** (deploy +1h) | **3.831s** | 0.523s | 1,045 | 🔴 Initial warm-up |
| **Fri 20:00** (deploy +3h) | **3.263s** | 0.274s | 636 | ⚠️ Settling |
| **Fri 23:00** (deploy +6h) | **0.867s** | — | low | ✅ Low traffic window |
| **Sat 08:00** (deploy +15h) | **2.720s** | — | rising | ⚠️ Morning traffic spike |
| **Sat 10:00** (deploy +17h) | **1.074s** | — | ~444 | ✅ Stabilized |
| **Sat 12:00** (deploy +19h) | **1.054s** | 0.321s | ~444 | ✅ Stable |
| **Sat 14:00** (deploy +21h) | **1.068s** | — | ~444 | ✅ Stable |

**Key insight:** The JEE10 warm-up takes approximately **17 hours** under traffic to fully stabilize. This matches the Jan 31 deployment pattern (which showed 2.6-3.1s sustained through Saturday — it had less time with daytime traffic to warm up before the Saturday measurement). This warm-up will recur on every deployment and pod restart.

### 🔴 Sunday Morning Spike (Feb 8, 10:00-11:00 CET) — Sustained

A P99 spike was observed on Sunday Feb 8, **sustained** across multiple measurement windows:

| Time (CET) | sis-ui P99 | Auth P99 | Context |
|------------|-----------|----------|---------||
| **Sun 08:00** | 0.268s | — | Very low traffic |
| **Sun 10:00** | **4.126s** | — | 🔴 Spike |
| **Sun 11:00** | **3.727s** | **0.500s** | 🔴 Still elevated |

This is **not an isolated transient event** — it persists for at least one hour. Possible explanations:
- **Overnight JIT/cache cool-down** — low overnight traffic may cause JIT-compiled code to be deoptimized, requiring re-warming
- **Sunday batch job execution** — needs verification against scheduled job configuration
- **GC pause chain** — needs GC log analysis
- **Inherent JEE10 warm-up fragility** — the JVM may lose optimization state during low-traffic periods

**Compared to Jan 31 weekend:** The Jan 31 sis-ui P99 was consistently elevated (2.6s-3.1s across all Saturday samples, never stabilized). This Feb 6 deployment shows improvement (Saturday stabilized at ~1.05s) but the Sunday relapse suggests **JEE10 latency stabilization is fragile** and may regress after low-traffic periods.

---

## Authenticator P99 — Persistent Regression

| Time | Jan 24 (JEE8) | Feb 7 (JEE10) | Delta |
|------|--------------|---------------|-------|
| Fri 18:00 CET (deploy +1h) | — | 0.523s | — (post-deploy warm-up) |
| Fri 20:00 CET (deploy +3h) | — | 0.274s | — (settling) |
| Sat 12:00 CET | 0.167s | 0.321s | **+92.2%** |
| Sun 11:00 CET | — | 0.500s | — (Sunday spike) |

The authenticator continues to show degraded P99 performance under JEE10:
- **Jan 31 (first weekend):** +44.7% (206ms → 298ms)
- **Feb 7 (second weekend):** +92.2% (167ms → 321ms)

This regression is **worsening**, not stabilizing. Investigation is recommended.

---

## Comparison to Jan 31 (First JEE10 Weekend)

| Component | Jan 31 P99 | Feb 7 P99 | Trend |
|-----------|-----------|-----------|-------|
| **sis-ui** | 3.120s | 1.054s | ✅ **Recovered** (-66.2%) |
| **ws-rest** | 0.824s | 0.807s | ✅ Stable (-2.1%) |
| **authenticator** | 0.298s | 0.321s | ⚠️ Worsening (+7.7%) |

---

## Queries Used
```promql
# P99 response time per component
histogram_quantile(0.99, sum(irate(traefik_service_request_duration_seconds_bucket{kubernetes_cluster="somtoday", namespace="traefik", exported_service=~".*-oop-sis-ui-.*"} [1m])) by (le))
histogram_quantile(0.99, sum(irate(traefik_service_request_duration_seconds_bucket{kubernetes_cluster="somtoday", namespace="traefik", exported_service=~".*-api-ws-rest-.*"} [1m])) by (le))
histogram_quantile(0.99, sum(irate(traefik_service_request_duration_seconds_bucket{kubernetes_cluster="somtoday", namespace="traefik", exported_service=~".*-inloggen-authenticator-.*"} [1m])) by (le))
histogram_quantile(0.99, sum(irate(traefik_service_request_duration_seconds_bucket{kubernetes_cluster="somtoday", namespace="traefik", exported_service=~".*-api-connect-rest-.*"} [1m])) by (le))

# P50 and P95
histogram_quantile(0.50, sum(irate(traefik_service_request_duration_seconds_bucket{kubernetes_cluster="somtoday", namespace="traefik", exported_service=~".*-oop-sis-ui-.*"} [1m])) by (le))
histogram_quantile(0.95, sum(irate(traefik_service_request_duration_seconds_bucket{kubernetes_cluster="somtoday", namespace="traefik", exported_service=~".*-oop-sis-ui-.*"} [1m])) by (le))
```
