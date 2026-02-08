# 🚀 Application Research: JEE10 Post-Release Weekend Comparison

**Comparison Window:** Feb 7-8, 2026 (Sat-Sun) vs Jan 24-25, 2026 (Sat-Sun)
**Context:** JEE10 (16.6.0) was deployed Jan 31. This is the second full weekend under JEE10.
**Previous Weekend (Jan 31-Feb 1):** Showed critical sis-ui P99 regression (+167%).

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
| **Sun 12:00** | 1.172s | *(no data yet)* | — | — |

### 🔴 Sunday Morning Spike (Feb 8, 10:00 CET)

A significant P99 spike to **4.126 seconds** was observed on Sunday Feb 8 at 10:00 CET. This is notable because:
- Saturday was consistently stable (~1.05-1.07s)
- Sunday 08:00 CET was very low (0.268s) — possibly low traffic
- The spike at 10:00 CET could be caused by:
  - **Batch job execution** (scheduled jobs running Sunday morning)
  - **Cache warming** after low-traffic overnight period
  - **GC pause** affecting the P99 window
  - **Actual regression** that surfaces under certain traffic patterns

**Compared to Jan 31 weekend:** The Jan 31 sis-ui P99 was consistently elevated (2.6s-3.1s across multiple Saturday samples). This Feb 8 spike appears more isolated, suggesting a transient event rather than a systemic regression.

---

## Authenticator P99 — Persistent Regression

| Time | Jan 24 (JEE8) | Feb 7 (JEE10) | Delta |
|------|--------------|---------------|-------|
| Sat 12:00 CET | 0.167s | 0.321s | **+92.2%** |
| Sun 10:00 CET | *(not queried)* | 0.673s | — |

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
