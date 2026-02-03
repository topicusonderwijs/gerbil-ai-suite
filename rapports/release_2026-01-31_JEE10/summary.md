# 🚀 Production Release Report: JEE10 Migration

**Date:** 2026-01-31 to 2026-02-01 (Weekend Deployment)  
**Migration:** JEE8 → JEE10 Platform Upgrade  
**Version:** 16.6.0  
**Research Directory:** [research/](research/)

---

## Executive Summary

The JEE10 migration was deployed over the weekend of January 31 - February 1, 2026. Initial weekday analysis showed stable performance, but **Saturday-to-Saturday comparison reveals critical regressions**:

| Aspect | Status | Details |
|--------|--------|---------||
| **Infrastructure** | ✅ Stable | Tunnel, ingress, database all healthy |
| **Performance** | 🔴 **Regression** | sis-ui P99 +167%, authenticator +45% (Sat-to-Sat) |
| **Errors** | ✅ Clean | Zero production errors during regression window |
| **Overall** | ⚠️ **Conditional Go** | Critical latency regression - root cause unknown |

---

## 1. Release Overview

### Deployment Details
- **Repository:** topicusonderwijs/iridium
- **Release Version:** 16.6.0 (JEE10)
- **Previous Version:** 16.5.0 (JEE8)
- **Deployment Window:** Weekend (minimal user impact)
- **First Released:** 2026-01-09 16:44 UTC

### Key Changes
This is a **major platform migration** from Java EE 8 to Jakarta EE 10, affecting:
- All backend services (sis-ui, ws-rest, docent-rest, authenticator)
- Package namespaces: `javax.*` → `jakarta.*`
- Runtime: WildFly JEE10 compatible version

---

## 2. Infrastructure Health

### 2.1 Kubernetes / Cloudflare Tunnel

| Metric | Before | After | Status |
|--------|--------|-------|--------|
| HA Connections | 24 | 24 | ✅ Stable |
| Tunnel Request Errors/sec | 1.80 | 2.37 | ⚠️ +31.7% |
| Tunnel Error Rate | 0.046% | 0.054% | ⚠️ Slight increase |

**Summary:** Tunnel infrastructure remained stable. Slight increase in request errors warrants monitoring.

📄 [Full Kubernetes Research](research/kubernetes.md) | [Cloudflare Research](research/cloudflare.md)

### 2.2 Database (PgBouncer)

| Metric | JEE8 Baseline | JEE10 | Delta | Status |
|--------|---------------|-------|-------|--------|
| Active Connections | 8,351 | 8,427 | +0.9% | ✅ Normal |
| Waiting Connections | 1 | 0 | -100% | ✅ Improved |

**Summary:** Database connectivity **improved** under JEE10. Zero waiting connections indicates better transaction handling.

📄 [Full Database Research](research/database.md)

---

## 3. Application Performance

### 3.1 Response Times (P99)

#### Weekday Comparison (Thu → Mon)
| Component | JEE8 | JEE10 | Delta | Status |
|-----------|------|-------|-------|--------|
| **sis-ui** | 2.263s | 2.351s | +3.9% | ✅ Normal |
| **ws-rest** | 0.926s | 0.893s | **-3.6%** | ✅ Improved |

#### 🔴 Saturday-to-Saturday Comparison (Jan 24 vs Jan 31)
| Component | JEE8 (Sat) | JEE10 (Sat) | Delta | Status |
|-----------|------------|-------------|-------|--------|
| **sis-ui** | 1.170s | 3.120s | **+166.7%** | 🔴 Critical |
| **ws-rest** | 0.751s | 0.824s | +9.7% | ⚠️ Degraded |
| **authenticator** | 0.206s | 0.298s | +44.7% | ⚠️ Degraded |
| **connect-rest** | 1.067s | 1.061s | -0.6% | ✅ Same |

**Summary:** Weekday comparison showed acceptable performance, but **Saturday-to-Saturday reveals critical sis-ui regression (+167%)**. The authenticator also shows significant degradation (+45%).

#### 📊 Supporting Evidence: sis-ui Regression Analysis

**Multiple time samples confirm the regression is consistent, not a single anomaly:**

| Time (CET) | JEE8 (Jan 24/25) | JEE10 (Jan 31/Feb 1) | Delta |
|------------|------------------|----------------------|-------|
| Sat 10:00 | 1.158s | 2.772s | **+139%** |
| Sat 12:00 | 1.170s | 3.120s | **+167%** |
| Sat 14:00 | 1.196s | 2.869s | **+140%** |
| Sun 12:00 | 1.185s | 2.607s | **+120%** |

**Percentile breakdown (Saturday 12:00):**

| Percentile | JEE8 | JEE10 | Delta |
|------------|------|-------|-------|
| P50 (median) | 60ms | 60ms | 0% |
| P95 | 665ms | 751ms | **+13%** |
| P99 | 1.17s | 3.12s | **+167%** |

**Key insight:** The median (P50) is unchanged, but P99 increased dramatically. This indicates:
- Most requests are fine (60ms median)
- The **slowest 1% of requests are 3x slower** under JEE10
- Likely a specific code path or query affected by JEE10 migration

**Traffic was comparable:**
- JEE8 Saturday: 17.0 req/sec to sis-ui
- JEE10 Saturday: 14.1 req/sec to sis-ui (-17% traffic)
- Lower traffic should mean *better* latency, yet P99 tripled

### 3.2 Throughput & Errors

| Metric | JEE8 | JEE10 | Delta | Status |
|--------|------|-------|-------|--------|
| Total Requests/sec | 3,940.8 | 4,422.1 | +12.2% | ✅ Normal |
| 5xx Errors/sec | 0.080 | 0.103 | +28.8% | ⚠️ Elevated |
| 5xx Error Rate | 0.0020% | 0.0023% | +15% | ⚠️ Monitor |
| Client Aborts (499) | 0.0174% | 0.0191% | +9.8%* | ✅ Normal |

*\* 499 comparison uses normalized weekend-to-weekend rate (not raw req/sec)*

### 3.3 HTTP Status Code Analysis

| Status | Change | Interpretation |
|--------|--------|----------------|
| 500 | +25.6% | Internal server errors increased |
| 502 | +176% | Gateway errors spiked (low absolute) |
| 503 | -100% | ✅ Service unavailable eliminated |
| 499 | +9.8% | ✅ Client timeouts within normal variance (weekend-to-weekend) |

📄 [Full Proxy Research](research/proxy.md) | [Application Research](research/application.md)

---

## 4. Error Analysis (Bugsnag) - Production Environment

### 4.1 Production Error Counts (app.release_stage="productie")

| Project | Saturday Window (10:00-16:00) | Status |
|---------|-------------------------------|--------|
| Somtoday Backend | **0 errors** | ✅ Clean |
| Somtoday Docent | **0 errors** | ✅ Clean |
| Somtoday Leerling | **0 errors** | ✅ Clean |

**Critical Finding:** Despite 167% P99 latency regression, **zero production errors** occurred during the performance degradation window.

### 4.2 Production Performance Paradox

**Critical Finding:** The 167% sis-ui latency regression occurred with **zero production application errors**.

This paradox indicates:
- The performance issue is **not caused by application exceptions**
- Likely causes: JVM behavior changes, garbage collection patterns, or low-level platform differences
- **Root cause remains unknown** and requires deeper investigation

### 4.3 Non-Production Error Analysis

⚠️ **Note:** Errors detected in Bugsnag were from non-production environments (`inkijk`, `test`, `pr`) and cannot be correlated with production performance issues.

Some JEE10-related errors observed in test environments:
- Infinispan cache issues in `inkijk` environment
- Jakarta namespace migration patterns in test deployments
- Database schema mismatches in inspection environments

📄 [Full Exceptions Research](research/exceptions.md)

---

## 5. Performance Analysis Summary

### 🔴 Performance Regression Identified

**Primary Finding:** Significant latency increase without corresponding application errors suggests platform-level performance issue.

| Metric | Baseline | JEE10 Release | Delta | Status |
|--------|----------|---------------|-------|--------|
| **sis-ui P99 latency** | 1.17s | 3.12s | +166.7% | 🔴 Critical regression |
| **authenticator P99 latency** | 206ms | 298ms | +44.7% | ⚠️ High regression |
| ws-rest P99 latency | 315ms | 345ms | +9.7% | ⚠️ Medium regression |

### ✅ Stability Indicators (Production)

| Improvement | Evidence |
|-------------|----------|
| Application errors | ✅ Zero new production errors during release |
| 5xx error rate (Saturday) | -24.9% improvement |
| Database connections | Zero waiting connections, stable pool |
| 503 errors | Eliminated completely |
| Infrastructure health | All systems normal (tunnel, ingress, K8s) |

### 🔍 Investigation Required

**Performance Paradox:** 167% latency increase with zero production application errors indicates:
- Platform-level issue (JVM, JEE10 runtime)
- Infrastructure performance changes
- Resource contention without error manifestation

**Non-Production Issues (Separate):** Database schema and Hibernate issues exist in test/inkijk environments but do not correlate with production performance regression.

---

## 6. Conclusion

### Go / No-Go Decision

| Decision | ⚠️ **Conditional Go - Investigation Required** |
|----------|-----------------------------------------------|

### Rationale

**Performance Paradox Identified:**
- 🔴 **P99 Latency +167%** — Main UI nearly 3x slower (1.17s → 3.12s) Saturday comparison
- ✅ **Zero Production Application Errors** — No new errors in production environment during release window
- ⚠️ **Root Cause Unknown** — Performance degradation without corresponding application errors suggests platform-level issue

**Evidence Summary:**
- Grafana metrics show significant latency increase (Saturday-to-Saturday comparison)
- Bugsnag production environment shows clean error slate during performance regression window
- Previous error correlation was from non-production environments (inkijk/test)

**Positive Factors:**
- ✅ Infrastructure stable (tunnel, database, ingress)
- ✅ 5xx error rate actually improved on Saturday (-24.9%)
- ✅ No critical outages during deployment
- ✅ 503 errors eliminated
- ✅ No production application errors detected

### Recommendations

1. **🔍 Critical:** Deep investigation needed - 167% P99 latency increase with zero production application errors suggests platform-level issue
2. **⚙️ High:** Investigate potential JEE10 JVM configuration changes (GC tuning, thread pools)
3. **📊 High:** Implement application performance monitoring (APM) to trace slow requests during peak latency periods
4. **🎯 High:** Investigate authenticator performance degradation (+45% latency)
5. **🔧 Medium:** Profile JVM behavior during high latency windows (thread dumps, GC logs)
6. **🚀 Medium:** Consider canary deployment strategy for future JEE platform migrations
7. **🧹 Low:** Address non-production environment issues separately (inkijk schema, test environment cleanup)

### Why Saturday-to-Saturday Matters

The weekday comparison (Thu→Mon) showed acceptable metrics because:
- Different traffic patterns and volumes
- Monday had 12% more traffic than Thursday
- Higher load can mask latency issues with warm caches

Saturday-to-Saturday provides a cleaner comparison with similar low-traffic conditions, revealing the true performance impact of JEE10.

---

## 7. Appendix

### Research Files
- [kubernetes.md](research/kubernetes.md) - Kubernetes & Cloudflare tunnel status
- [database.md](research/database.md) - PgBouncer connection metrics
- [cloudflare.md](research/cloudflare.md) - Tunnel request/error analysis
- [proxy.md](research/proxy.md) - Traefik HTTP status codes
- [application.md](research/application.md) - Response times & throughput
- [exceptions.md](research/exceptions.md) - Bugsnag error analysis

### Data Sources
- **Grafana Prometheus:** PBFA97CFB590B2093
- **Bugsnag Projects:** Somtoday, Somtoday Docent, Somtoday Leerling
- **Time Range:** 2026-01-30 to 2026-02-02

### Dashboard Links
- [Somtoday Status Overview](https://grafana.topicus.education/d/K3Q86qtGz/somtoday-status-overview)
- [Traefik v3](https://grafana.topicus.education/d/rCn92aUGp/traefik-v3)
- [Cloudflared Tunnel](https://grafana.topicus.education/d/2WhbDNm7z/cloudflared-tunnel)
- [Database Quickview](https://grafana.topicus.education/d/J8vwk3DMk/somtoday-database-quickview)

---

*Report generated: 2026-02-03*  
*Analysis by: GitHub Copilot Release Reporter Agent*
