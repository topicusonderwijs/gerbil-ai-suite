# 🚀 Production Release Report: JEE10 Migration

**Date:** 2026-01-31 to 2026-02-01 (Weekend Deployment)  
**Migration:** JEE8 → JEE10 Platform Upgrade  
**Version:** 16.6.0  
**Research Directory:** [research/](research/)

---

## Executive Summary

The JEE10 migration was deployed over the weekend of January 31 - February 1, 2026. Overall system health remained **stable** with no critical outages. However, several **potential regressions** were identified that require monitoring:

| Aspect | Status | Details |
|--------|--------|---------|
| **Infrastructure** | ✅ Stable | Tunnel, ingress, database all healthy |
| **Performance** | ⚠️ Mixed | WS-REST improved, slight 5xx increase |
| **Errors** | ⚠️ Monitor | New Infinispan cache errors detected |
| **Overall** | ⚠️ **Conditional Go** | Requires monitoring |

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

| Component | JEE8 | JEE10 | Delta | Status |
|-----------|------|-------|-------|--------|
| **sis-ui** | 2.263s | 2.351s | +3.9% | ✅ Normal |
| **ws-rest** | 0.926s | 0.893s | **-3.6%** | ✅ Improved |

**Summary:** Mixed results. WS-REST **improved** by 3.6%, while SIS-UI showed minor 3.9% degradation (within acceptable variance).

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

## 4. Error Analysis (Bugsnag)

### 4.1 Error Counts

| Project | JEE10 Period | Baseline (JEE8) | Trend |
|---------|--------------|-----------------|-------|
| Somtoday Backend | 311 errors | 411 errors | ⬇️ -24% |
| Somtoday Docent | 59 errors | - | - |
| Somtoday Leerling | 65 errors | - | - |

### 4.2 NEW Errors (Potential Regressions) 🔴

| Error | Events | Component | Severity |
|-------|--------|-----------|----------|
| **Infinispan CacheEntry NPE** | 129 | REST | 🔴 High |
| `jakarta.transaction.RollbackException` | 297+ | REST | ⚠️ Medium |
| FetchError ETIMEDOUT (docent-rest) | 1,121 | Docent | ⚠️ Medium |

#### Critical: Infinispan Cache NullPointerException
```
Cannot invoke "org.infinispan.container.entries.CacheEntry.isRemoved()" 
because "entry" is null
```
- **Location:** `LeerlingContextPermissionResolver.java:116`
- **First Seen:** 2026-01-31 09:07 (immediately after deployment)
- **Impact:** 129 events, affecting permission resolution

This is a **potential JEE10 compatibility issue** with Infinispan distributed cache.

### 4.3 Jakarta Namespace Migration

Evidence of JEE8 → JEE10 transition in error classes:

| Package | Version | Errors |
|---------|---------|--------|
| `javax.transaction.*` | JEE8 | 2,185+ |
| `jakarta.transaction.*` | JEE10 | 297+ |

Both namespaces appearing indicates transitional state during migration.

📄 [Full Exceptions Research](research/exceptions.md)

---

## 5. Identified Regressions

### Confirmed Issues

| Issue | Severity | Evidence | Action |
|-------|----------|----------|--------|
| Infinispan NPE | 🔴 High | 129 events, new error class | Investigate cache compatibility |
| 5xx error increase | ⚠️ Medium | +28.8% rate | Monitor trends |

### Improvements

| Improvement | Evidence |
|-------------|----------|
| WS-REST response time | -3.6% P99 latency |
| Database connections | Zero waiting connections |
| 503 errors | Eliminated completely |
| Client timeouts (499) | Only +9.8% (weekend-to-weekend), not 32.6% |

---

## 6. Conclusion

### Go / No-Go Decision

| Decision | ⚠️ **Conditional Go** |
|----------|----------------------|

### Rationale

**Positive Factors:**
- ✅ Infrastructure stable (tunnel, database, ingress)
- ✅ WS-REST performance improved
- ✅ No critical outages during deployment
- ✅ 503 errors eliminated

**Concerns:**
- ⚠️ New Infinispan cache errors require investigation
- ⚠️ 5xx error rate increased (still <0.01% of traffic)

### Recommendations

1. **Immediate:** Investigate Infinispan `CacheEntry.isRemoved()` NPE in `LeerlingContextPermissionResolver`
2. **Short-term:** Monitor 5xx error trends over next 48 hours
3. **Ongoing:** Track jakarta.* vs javax.* error ratio as migration completes

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
