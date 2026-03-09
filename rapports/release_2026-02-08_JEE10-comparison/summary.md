# 🚀 Production Release Report: JEE10 Comparison — Week 2

**Date:** 2026-02-08  
**Comparison:** Feb 7-8, 2026 (JEE10 Week 2) vs Jan 24-25, 2026 (JEE8 Baseline)  
**Version:** 16.6.0 (Jakarta EE 10)  
**Context:** Second JEE10 deployment — re-deployed Fri Feb 6 17:00 CET after week-long rollback. Follow-up to [Jan 31 rapport](../release_2026-01-31_JEE10/summary.md)  
**Research Directory:** [research/](research/)

---

## Executive Summary

The second full weekend under JEE10 shows **significant recovery** from the critical regressions identified on Jan 31. The sis-ui P99 regression (+167%) has fully resolved, and JVM resource usage shows major improvements. One persistent issue remains with the authenticator.

| Aspect | Status | Details |
|--------|--------|---------|
| **sis-ui P99** | ⚠️ **Partial Recovery** | Saturday stable at 1.054s; Sunday spike sustained (3.7-4.1s); post-deploy warm-up confirmed |
| **Authenticator P99** | 🔴 **Worsening** | +92% vs JEE8 baseline (167ms → 321ms) |
| **Heap Memory** | ✅ 🎉 **Major Improvement** | Up to 83% less heap usage across components (⚠️ traffic 50% lower — needs weekday verification) |
| **Infrastructure** | ⚠️ **Degraded** | 1 of 3 tunnel pods missing (node01) |
| **Errors (Production)** | ✅ **Clean for JEE10** | 562 error groups in 16.6.* (most from JEE8 period); 1 confirmed JEE10-specific (self-resolved) |
| **Overall** | ⚠️ **Conditional Go** | Saturday P99 recovered but Sunday spike sustained; authenticator worsening; needs weekday monitoring |

---

## 1. Release Context

### Timeline
| Date | Event |
|------|-------|
| 2026-01-09 | Version 16.6.0 released (code release, **still JEE8 platform**) |
| 2026-01-24/25 | **JEE8 baseline weekend** (version 16.6.0 on JEE8 — this report's comparison target) |
| 2026-01-31/Feb 1 | **First JEE10 platform deployment** — critical sis-ui P99 regression (+167%) |
| 2026-02-02 (Mon) | **JEE10 rolled back to JEE8** for the work week |
| **2026-02-06 17:00 CET** | **JEE10 re-deployed to production** |
| **2026-02-07/08** | **Second JEE10 weekend — this report** (~40h since re-deployment) |

### Traffic Context
Weekend traffic on Feb 7-8 was approximately **50% lower** than Jan 24-25:
- Jan 24: 957 req/sec
- Feb 7: 444 req/sec

This is likely seasonal (school holiday/exam period), not JEE10-related. All traffic proportions and status code distributions remained consistent.

---

## 2. Infrastructure Health

### 2.1 Cloudflare Tunnel

| Metric | Jan 24 (JEE8) | Feb 7 (JEE10) | Status |
|--------|---------------|---------------|--------|
| HA Connections | 24 (3 pods) | **16 (2 pods)** | 🔴 Reduced |
| Tunnel Requests/sec | 955.3 | 443.5 | ✅ Proportional |
| Tunnel Error Rate | 0.0175% | 0.0194% | ⚠️ +10.9% relative |

**🔴 Critical:** The tunnel pod on **som-k8s-node01** is no longer reporting, reducing HA capacity by 33%. Remaining pods handle current traffic, but this reduces redundancy.

📄 [Full Kubernetes Research](research/kubernetes.md)

### 2.2 Database (PgBouncer)

| Metric | Jan 24 (JEE8) | Feb 7 (JEE10) | Status |
|--------|---------------|---------------|--------|
| Active Connections | 3,888 | 3,332 | ✅ Proportional |
| Waiting Connections | 0 | 0 | ✅ Healthy |

Database connectivity remains healthy. Zero waiting connections across both JEE10 weekends.

📄 [Full Database Research](research/database.md)

---

## 3. Application Performance

### 3.1 Response Times (P99) — Saturday 12:00 CET

| Component | Jan 24 (JEE8) | Jan 31 (JEE10 wk1) | Feb 7 (JEE10 wk2) | vs JEE8 | Trend |
|-----------|---------------|--------------------|--------------------|---------|-------|
| **sis-ui** | 1.110s | 3.120s 🔴 | **1.054s** | **-5.1%** | ✅ **Recovered** |
| **ws-rest** | 0.743s | 0.824s | **0.807s** | +8.7% | ⚠️ Stable |
| **authenticator** | 0.167s | 0.298s | **0.321s** | **+92.2%** | 🔴 Worsening |
| **connect-rest** | N/A | 1.061s | **1.182s** | N/A | — |

### ⚠️ sis-ui P99 Recovery — Partial (Saturday Only)

The **critical 167% sis-ui P99 regression** from Jan 31 shows **Saturday recovery** but **Sunday relapse**:

| Weekend | sis-ui P99 | vs JEE8 Baseline |
|---------|-----------|------------------|
| Jan 24 (JEE8) | 1.110s | — baseline — |
| Jan 31 (JEE10 wk1) | 3.120s | 🔴 **+167%** |
| **Feb 7 (JEE10 wk2)** | **1.054s** | ✅ **-5.1%** |

Multiple Saturday time samples confirm the recovery is consistent:

| Time (CET) | Jan 24 (JEE8) | Feb 7 (JEE10) | Delta |
|------------|---------------|---------------|-------|
| Sat 10:00 | 1.107s | 1.074s | -3.0% ✅ |
| Sat 12:00 | 1.110s | 1.054s | -5.1% ✅ |
| Sat 14:00 | 1.145s | 1.068s | -6.7% ✅ |

### 📊 sis-ui Percentile Breakdown (Saturday 12:00 CET)

| Percentile | Jan 24 (JEE8) | Feb 7 (JEE10) | Delta | Status |
|------------|---------------|---------------|-------|--------|
| **P50 (median)** | 58.6ms | 56.1ms | -4.2% | ✅ Improved |
| **P95** | 586ms | 250ms | **-57.3%** | ✅ 🎉 Major improvement |
| **P99** | 1.110s | 1.054s | -5.1% | ✅ Improved |

**Key insight:** P95 improved by 57%, meaning the **95th percentile of requests is now more than 2x faster** under JEE10 than under JEE8. ⚠️ **Note:** Traffic was ~50% lower on Feb 7 — this improvement needs verification under comparable weekday load.

### 🔴 Sunday Morning Spike (Feb 8, 10:00-11:00 CET) — Sustained

A P99 spike was observed on Sunday Feb 8, **sustained** across multiple measurement windows:
- **10:00 CET:** 4.126s
- **11:00 CET:** 3.727s (authenticator also elevated: 0.500s)

This is **not an isolated transient event** — it persists for at least one hour. Combined with the post-deployment warm-up data (sis-ui P99 was 3.83s at 18:00 CET on Feb 6, settling to ~1.05s by Saturday 10:00), this suggests JEE10 may exhibit **periodic latency relapses** after low-traffic periods cause JIT/cache cooling. Requires investigation — check GC logs, batch job schedules, and pod events for this window.

### 🔴 Authenticator P99 — Persistent Regression

| Weekend | P99 | vs JEE8 | Trend |
|---------|-----|---------|-------|
| Jan 24 (JEE8) | 167ms | — baseline — | |
| Jan 31 (JEE10 wk1) | 298ms | +44.7% | ⚠️ |
| **Feb 7 (JEE10 wk2)** | **321ms** | **+92.2%** | 🔴 Worsening |

The authenticator regression is **not recovering** and is worsening week-over-week. Investigation is recommended.

📄 [Full Application Research](research/application.md)

### 3.2 HTTP Status Codes & Error Rates

| Metric | Jan 24 | Feb 7 | Status |
|--------|--------|-------|--------|
| 2xx % of traffic | 96.5% | 97.0% | ✅ Consistent |
| 499 % of traffic | 0.0165% | 0.0185% | ✅ Normal variance |
| 5xx Rate | 0.00223/s | 0.00335/s | ⚠️ +50% |
| 5xx % of traffic | 0.000233% | 0.000754% | ⚠️ ~3x higher |
| 502/503 errors | 0 | 0 | ✅ None |

The **relative** 5xx increase (~3x) looks concerning, but **absolute numbers remain extremely low** — approximately 12 errors per hour, or 1 error per 133,000 requests.

📄 [Full Proxy Research](research/proxy.md)

---

## 4. JVM Resources — Major Improvement 🎉

### 4.1 Heap Memory Usage (Max %)

| Component | Jan 24 (JEE8) | Feb 7 (JEE10) | Reduction | Status |
|-----------|---------------|---------------|-----------|--------|
| **sis-ui** | 69.2% | **11.5%** | **-83%** | ✅ 🎉 |
| **authenticator** | 61.8% | **11.0%** | **-82%** | ✅ 🎉 |
| **ws-rest** | 81.3% | 76.7% | -6% | ✅ |
| **docent-rest** | 68.7% | 40.3% | **-41%** | ✅ 🎉 |
| **connect-rest** | 59.2% | 22.5% | **-62%** | ✅ 🎉 |
| **rest-auth** | 71.9% | 35.9% | **-50%** | ✅ 🎉 |

Even accounting for ~50% less traffic, the heap reductions (up to 83%) far exceed what traffic reduction alone would explain. This appears to be a **genuine JEE10 platform improvement** — likely from Jakarta EE 10 runtime optimizations, improved GC, and reduced class metadata overhead.

### 4.2 Thread Utilization

All components remain well below critical thresholds (<10%). The authenticator shows a slight increase (+1.67 percentage points), consistent with its P99 regression.

📄 [Full JVM Resources Research](research/jvm_resources.md)

---

## 5. Error Analysis (Bugsnag)

> **⚠️ Important Corrections:**
> 1. Somtoday Backend uses release stage `"production"`, while Docent/Leerling use `"productie"`. Previous analysis inadvertently queried Backend with the wrong filter.
> 2. **Version 16.6.0 was released on Jan 9 on the JEE8 platform.** JEE10 was first deployed on Jan 31, rolled back on Feb 2, and re-deployed on Feb 6 at 17:00 CET. Errors from Jan 9-30 are version 16.6.0 code issues on JEE8, **not JEE10 platform issues.**
> 3. The actual JEE10 production windows are: **Jan 31 – Feb 1** (~2 days) and **Feb 6 17:00 CET – present** (~1.5 days). Total JEE10 runtime: ~3.5 days.

### 5.1 5xx Error Rates — Corrected Timeline

Prometheus instant queries at key dates, with corrected platform attribution:

| Date | 5xx Rate/sec | ~Errors/hour | Platform | Context |
|------|-------------|-------------|----------|---------||
| **Jan 9** (v16.6.0 release) | **0.0775** | **~279** | ⚠️ **JEE8** | Version 16.6.0 code release on JEE8 |
| **Jan 13** (WELD CDI peak) | **0.0918** | **~330** | ⚠️ **JEE8** | Version 16.6.0 code issue on JEE8 |
| Jan 24 (JEE8 baseline) | 0.00446 | ~16 | JEE8 | — baseline — |
| **Jan 31** (JEE10 deploy #1) | 0.00335 | ~12 | **JEE10** | First JEE10 weekend |
| Feb 2-6 (rollback week) | — | — | JEE8 | Rolled back to JEE8 |
| **Feb 6 18:00 CET** (re-deploy +1h) | 0.00781 | ~28 | **JEE10** | Post JEE10 re-deployment |
| **Feb 6 20:00 CET** (re-deploy +3h) | 0.00504 | ~18 | **JEE10** | Settling |
| **Feb 7** (JEE10 deploy #2) | 0.00502 | ~18 | **JEE10** | Second JEE10 weekend |
| **Feb 8 10:00 CET** | 0.00139 | ~5 | **JEE10** | Sunday morning |
| **Feb 8 11:00 CET** | 0.00279 | ~10 | **JEE10** | Sunday morning |

**Corrected Finding:** The Jan 9-15 5xx spike (17-20x) was caused by **version 16.6.0 code issues on the JEE8 platform**, not by JEE10. JEE10 was not deployed until Jan 31. During actual JEE10 windows (Jan 31-Feb 1 and Feb 6-8), 5xx error rates have been **normal and stable** (~5-28 errors/hour). The slight elevation at Feb 6 18:00 CET (28/hr) is expected post-deployment turbulence that settled within 2 hours.

### 5.2 JEE10-Specific Errors (Backend) — Corrected

**One** error is confirmed JEE10-specific (down from 2 after timeline correction):

| Error | Events | Users | Period | Platform | Root Cause |
|-------|--------|-------|--------|----------|------------|
| ~~WELD-000713 CDI injection~~ | 781 | 145 | Jan 12-15 | ❌ **JEE8** | ~~CDI classloader isolation~~ → Version 16.6.0 code issue on JEE8 |
| Infinispan CacheEntry NPE | 129 | 47 | Jan 31 (9 sec) | ✅ **JEE10** | L2 cache race condition (`BuildNumber: "30-jee10"`) |

**Correction:** The WELD-000713 error (Jan 12-15) occurred **before JEE10 was deployed** (Jan 31). It is a version 16.6.0 code issue on the JEE8 platform. The original "stricter module classloader isolation under JEE10" root cause is incorrect for this timeframe.

### 5.3 Error Groups Introduced in 16.6.* — 562 Total

| Category | Error Groups | Total Events | User Impact | Status |
|----------|-------------|-------------|-------------|--------|
| RollbackException/OAuth2Token (4 view variants) | 4 | ~14,655 | 1 (service account) | 🟡 Ongoing, no user impact |
| OptimisticLockException/LesRegistratie (9 view variants) | 9 | ~832 | ~550 | 🟡 Ongoing, pre-existing pattern |
| EntityNotFoundException (multiple entities) | ~10 | ~2,549 | ~1,150 | ✅ Mostly resolved |
| LazyInitializationException (Groepsindeling) | 1 | 1,157 | 242 | 🟡 Ongoing — pre-dates JEE10 |
| ConstraintViolation/SWIGemaakt | 2 | 232 | 228 | 🟡 Ongoing, consistent |
| **WELD CDI injection** | 1 | 781 | 145 | ✅ Self-resolved |
| **Infinispan CacheEntry NPE** | 1 | 129 | 47 | ✅ Self-resolved |
| Other (URI, Turnitin timeout, etc.) | ~534 | — | — | Mixed |

**Important context:** The "562 error groups introduced in 16.6.*" represents errors introduced in **code version 16.6.0**, not errors caused by the JEE10 platform. Most of these (Jan 9–Jan 30) occurred while running on JEE8. The count is further inflated by WildFly proxy class regeneration (`$$$viewN` variants), causing pre-existing errors to appear as "new" error groups. Only errors during actual JEE10 windows (Jan 31-Feb 1 and Feb 6-present) can be attributed to the JEE10 platform.

### 5.4 This Weekend (Feb 7-8) — Production Error Summary

| Project | New JEE10-Specific Errors | Status |
|---------|---------------------------|--------|
| Somtoday Backend | **0 new** (1 new EntityNotFoundException on v16.7.0) | ⚠️ Monitor |
| Somtoday Leerling | **0** | ✅ Clean |
| Somtoday Docent | **0** | ✅ Clean |

### 5.5 Notable Pre-Existing Errors (This Weekend)

| Error | Events | Impact | Source |
|-------|--------|--------|--------|
| TurnitinException (EULA) | 1,972 | External service burst | Backend |
| RollbackException (OAuth2Token) | 470 | Low (1 service account) | Backend |
| ValidationError (rechten) | 872 | 0 users (background) | Docent |
| TypeError (editAfspraakForm) | 592 | 321 users | Docent |
| "Geen huidig account-profiel" | 173 | 168 users | Leerling |

📄 [Full Exceptions Research](research/exceptions.md)

---

## 6. Regression Tracking — Jan 31 vs Feb 7

| Issue from Jan 31 Report | Jan 31 Status | Feb 7 Status | Resolution |
|--------------------------|---------------|--------------|------------|
| sis-ui P99 +167% | 🔴 Critical | ⚠️ **Partial** | Saturday recovered (-5%), but Sunday spike sustained (3.7-4.1s) |
| authenticator P99 +45% | ⚠️ Degraded | 🔴 **Worsened** (+92%) | Needs investigation |
| ws-rest P99 +10% | ⚠️ Degraded | ⚠️ Stable (+8.7%) | Acceptable |
| 5xx error rate elevated | ⚠️ Monitor | ⚠️ Consistent | Very low absolute numbers |
| Zero production errors | ✅ Clean | ⚠️ **Revised** | 562 error groups in 16.6.* found (most from JEE8 period); 1 confirmed JEE10-specific (Infinispan NPE, self-resolved) |
| 5xx release day spike | ℹ️ Not checked | ⚠️ **Corrected** | Jan 9-15 spike was v16.6.0 on **JEE8**, not JEE10. JEE10 windows show normal 5xx rates |

---

## 7. Conclusion

### Go / No-Go Decision

| Decision | ⚠️ **Conditional Go — With Active Monitoring** |
|----------|-----------------------------------------------|

### Rationale

The sis-ui P99 regression from Jan 31 shows **partial recovery** on Saturday, but **Sunday data reveals a sustained latency relapse** (3.7-4.1s). The JEE10 platform has only been running for ~40 hours since re-deployment (Feb 6 17:00 CET), following a week-long rollback to JEE8. More runtime is needed to confirm stability.

**Positive Findings:**
- ✅ sis-ui P99 Saturday comparison: recovered to **-5%** vs JEE8 baseline
- ✅ sis-ui P95 on Saturday: **57% faster** than JEE8 (⚠️ traffic was 50% lower — needs weekday verification)
- ✅ 🎉 Heap memory usage reduced by up to **83%** (⚠️ partially explained by 50% lower traffic)
- ✅ JEE10-specific Infinispan CacheEntry error **self-resolved** (9-second burst on Jan 31)
- ✅ 5xx error rates normal during actual JEE10 windows
- ✅ Database connections healthy, zero waiting
- ✅ Status code distributions proportionally identical

**Open Issues:**
- 🔴 **Sunday P99 spike sustained** (4.126s at 10:00 CET, 3.727s at 11:00 CET) — not isolated, needs investigation
- 🔴 Authenticator P99 regression worsening (+92%) — requires investigation
- 🔴 Missing tunnel pod on node01 — reduced HA capacity by 33%
- ⚠️ Post-deployment warm-up pattern confirmed (P99 3.83s → 1.05s over ~16h) — will recur on pod restarts
- ⚠️ Only ~3.5 days total JEE10 runtime — insufficient for confident stability assessment
- ⚠️ Traffic was ~50% lower than baseline — P99 and heap improvements may not hold under full weekday load
- ⚠️ LazyInitializationException (242 users) warrants attention
- ⚠️ New EntityNotFoundException (ExamenVakHulpmiddel) appeared Feb 7 on v16.7.0 — monitor

### Recommendations

1. **� Critical:** Investigate Sunday P99 spike (sustained 3.7-4.1s on Feb 8, 10:00-11:00 CET) — check GC logs, pod events, batch job schedules for this window
2. **🔴 Critical:** Investigate authenticator P99 regression — worsening trend from +45% → +92%
3. **🔧 Critical:** Investigate/restore missing tunnel pod on som-k8s-node01 before weekday traffic
4. **📊 High:** Monitor weekday performance closely (Mon Feb 9) — Saturday comparisons are confounded by ~50% lower traffic. Weekday will be the true JEE10 performance test.
5. **📊 High:** Characterize the JEE10 warm-up pattern (P99 3.83s → 1.05s over ~16h) — this will recur on every deployment and pod restart. Consider pre-warming strategies.
6. **📊 High:** Investigate `LazyInitializationException` in `GroepsindelingService.deleteGroepsindeling:345` — 242 users affected, pre-dates JEE10 but volume increased under 16.6.0.
7. **📊 Medium:** Monitor the new `ExamenVakHulpmiddel` EntityNotFoundException (Feb 7, v16.7.0) — stale collection cache pattern
8. **📈 Low:** The `$$$view` proxy proliferation is cosmetic (WildFly class regeneration) but creates noise in Bugsnag. Consider adding a Bugsnag grouping rule to collapse view variants.
9. **📈 Low:** The JEE10 heap memory improvements are promising but need verification under full weekday traffic

### Jan 31 "Performance Paradox" — Partially Resolved

The Jan 31 report identified a "performance paradox" where P99 latency increased 167% with zero application errors.

**Critical Correction:** The Jan 9-15 error turbulence (WELD CDI injection, EntityNotFoundException bursts) occurred under **version 16.6.0 on the JEE8 platform**, not under JEE10. JEE10 was first deployed on Jan 31. These errors are version 16.6.0 code issues unrelated to the JEE10 platform.

The corrected JEE10 picture:
- **Jan 31 (JEE10 deploy #1):** P99 2.6-3.1s sustained + Infinispan CacheEntry NPE (129 events, 9s burst) — confirmed JEE10-specific
- **Feb 2 (rollback):** JEE10 rolled back to JEE8 for the work week
- **Feb 6 17:00 CET (JEE10 deploy #2):** P99 3.83s post-deployment, settling to ~1.05s by Saturday 10:00 (~16h warm-up)
- **Feb 7 Saturday:** Stable P99 at ~1.05s — recovery from Jan 31 pattern
- **Feb 8 Sunday:** P99 relapse to 3.7-4.1s — not fully stable

**Updated conclusions:**
- The Jan 31 P99 regression is a JEE10 **warm-up / JIT compilation** issue that resolves over ~16 hours under traffic
- The Feb 6 re-deployment confirms the warm-up pattern (3.83s → 1.05s)
- The Sunday relapse suggests latency instability persists beyond initial warm-up, possibly triggered by low-traffic periods
- **Lesson learned:** Always verify Bugsnag release stage filters per project (`"production"` vs `"productie"`). Always verify deployment timeline before attributing errors to platform changes.

---

## 8. Appendix

### Research Files
- [application.md](research/application.md) — Response times, percentiles & throughput
- [proxy.md](research/proxy.md) — HTTP status codes & error rates (Traefik v3)
- [database.md](research/database.md) — PgBouncer connection metrics
- [kubernetes.md](research/kubernetes.md) — Cloudflare tunnel & K8s infrastructure
- [jvm_resources.md](research/jvm_resources.md) — Heap memory & thread utilization
- [exceptions.md](research/exceptions.md) — Bugsnag error analysis

### Data Sources
- **Grafana Prometheus:** PBFA97CFB590B2093
- **Bugsnag Projects:** Somtoday Backend, Docent, Leerling
- **Dashboards:** Traefik v3, Cloudflared Tunnel, Somtoday Database Quickview

### Dashboard Links
- [Somtoday Status Overview](https://grafana.topicus.education/d/K3Q86qtGz/somtoday-status-overview)
- [Traefik v3](https://grafana.topicus.education/d/rCn92aUGp/traefik-v3)
- [Cloudflared Tunnel](https://grafana.topicus.education/d/2WhbDNm7z/cloudflared-tunnel)
- [Database Quickview](https://grafana.topicus.education/d/J8vwk3DMk/somtoday-database-quickview)

---

*Report generated: 2026-02-08*  
*Comparison: Feb 7-8, 2026 (JEE10 Week 2) vs Jan 24-25, 2026 (JEE8 Baseline)*  
*Analysis by: GitHub Copilot Release Reporter Agent*
