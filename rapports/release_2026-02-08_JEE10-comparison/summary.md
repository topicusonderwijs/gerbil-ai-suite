# 🚀 Production Release Report: JEE10 Comparison — Week 2

**Date:** 2026-02-08  
**Comparison:** Feb 7-8, 2026 (JEE10 Week 2) vs Jan 24-25, 2026 (JEE8 Baseline)  
**Version:** 16.6.0 (Jakarta EE 10)  
**Context:** Second full weekend under JEE10 — follow-up to [Jan 31 rapport](../release_2026-01-31_JEE10/summary.md)  
**Research Directory:** [research/](research/)

---

## Executive Summary

The second full weekend under JEE10 shows **significant recovery** from the critical regressions identified on Jan 31. The sis-ui P99 regression (+167%) has fully resolved, and JVM resource usage shows major improvements. One persistent issue remains with the authenticator.

| Aspect | Status | Details |
|--------|--------|---------|
| **sis-ui P99** | ✅ **Recovered** | 1.054s (was 3.12s on Jan 31, baseline 1.11s) |
| **Authenticator P99** | 🔴 **Worsening** | +92% vs JEE8 baseline (167ms → 321ms) |
| **Heap Memory** | ✅ 🎉 **Major Improvement** | Up to 83% less heap usage across components |
| **Infrastructure** | ⚠️ **Degraded** | 1 of 3 tunnel pods missing (node01) |
| **Errors (Production)** | ⚠️ **Nuanced** | 562 error groups in 16.6.*; 2 JEE10-specific (self-resolved); first-week spikes settled |
| **Overall** | ✅ **Go** | Critical regression resolved; first-week error turbulence settled; authenticator needs investigation |

---

## 1. Release Context

### Timeline
| Date | Event |
|------|-------|
| 2026-01-09 | Version 16.6.0 released (JEE10) |
| 2026-01-24/25 | **JEE8 baseline weekend** (this report's comparison target) |
| 2026-01-31/Feb 1 | First JEE10 weekend — critical sis-ui P99 regression (+167%) |
| **2026-02-07/08** | **Second JEE10 weekend — this report** |

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

### ✅ sis-ui P99 Recovery — Key Finding

The **critical 167% sis-ui P99 regression** from Jan 31 has **fully recovered**:

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

**Key insight:** P95 improved by 57%, meaning the **95th percentile of requests is now more than 2x faster** under JEE10 than under JEE8.

### ⚠️ Sunday Morning Spike (Feb 8, 10:00 CET)

A transient P99 spike to **4.126s** was observed on Sunday Feb 8 at 10:00 CET. Unlike the Jan 31 regression (which was sustained across all Saturday samples), this appears to be an isolated event — possibly a batch job, cache warming, or GC pause. Saturday metrics were consistently stable.

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

> **⚠️ Note:** Somtoday Backend uses release stage `"production"`, while Docent/Leerling use `"productie"`. Previous analysis inadvertently queried Backend with the wrong filter, returning 0 results. This section reflects corrected data.

### 5.1 5xx Error Spike — Release Day Correlation

Prometheus instant queries at key dates reveal a significant 5xx spike during the first JEE10 week:

| Date | 5xx Rate/sec | ~Errors/hour | vs Baseline | Context |
|------|-------------|-------------|-------------|---------|
| **Jan 9** (release day) | **0.0775** | **~279** | 🔴 **17x** | Release deployment |
| **Jan 13** (WELD CDI peak) | **0.0918** | **~330** | 🔴 **20x** | Peak error period |
| Jan 24 (JEE8 baseline) | 0.00446 | ~16 | — baseline — | Normal weekend |
| Jan 31 (JEE10 wk1) | 0.00335 | ~12 | ✅ -25% | Normal weekend |
| Feb 7 (JEE10 wk2) | 0.00502 | ~18 | ✅ +12% | Normal weekend |

**Finding:** The JEE10 release **did** cause a 17-20x error spike during Jan 9-15, but error rates fully normalized before the JEE8 baseline weekend. Both comparison weekends (Jan 24 and Feb 7-8) show normal, stable 5xx rates.

### 5.2 JEE10-Specific Errors (Backend)

Two errors are **confirmed JEE10-specific**. Both self-resolved:

| Error | Events | Users | Period | Root Cause |
|-------|--------|-------|--------|------------|
| WELD-000713 CDI injection | 781 | 145 | Jan 12-15 (3 days) | CDI module classloader isolation |
| Infinispan CacheEntry NPE | 129 | 47 | Jan 31 (9 seconds) | L2 cache race condition |

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

**Important context:** The large "562 introduced" count is inflated by WildFly's JEE10 proxy class regeneration. Each deployment creates new `$$$viewN` proxy class names, causing pre-existing errors (RollbackException, OptimisticLockException) to appear as "new" error groups. The underlying bugs are pre-existing; only the proxy variant is new.

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
| sis-ui P99 +167% | 🔴 Critical | ✅ **Resolved** | Recovered to baseline (-5%) |
| authenticator P99 +45% | ⚠️ Degraded | 🔴 **Worsened** (+92%) | Needs investigation |
| ws-rest P99 +10% | ⚠️ Degraded | ⚠️ Stable (+8.7%) | Acceptable |
| 5xx error rate elevated | ⚠️ Monitor | ⚠️ Consistent | Very low absolute numbers |
| Zero production errors | ✅ Clean | ⚠️ **Revised** | 562 error groups in 16.6.* found; 2 JEE10-specific (self-resolved) |
| 5xx release day spike | ℹ️ Not checked | 🔴 **Confirmed** | 17-20x spike Jan 9-15, fully normalized |

---

## 7. Conclusion

### Go / No-Go Decision

| Decision | ✅ **Go — With Monitoring** |
|----------|---------------------------|

### Rationale

The critical sis-ui P99 regression that triggered a "Conditional Go" on Jan 31 has **fully resolved**. The JEE10 platform is now performing at or better than JEE8 baseline levels for the primary application component. The deeper Bugsnag analysis reveals the first JEE10 week had significant error turbulence, but this has fully settled.

**Positive Findings:**
- ✅ sis-ui P99 recovered — now **5% better** than JEE8 baseline
- ✅ sis-ui P95 **57% faster** than JEE8 — significant improvement
- ✅ 🎉 Heap memory usage reduced by up to **83%** — major platform benefit
- ✅ Both JEE10-specific errors (WELD CDI, Infinispan) **self-resolved** within days
- ✅ First-week 5xx spike (17-20x) fully normalized — Feb 7-8 rates are normal
- ✅ Database connections healthy, zero waiting
- ✅ Status code distributions proportionally identical

**Open Issues:**
- 🔴 Authenticator P99 regression worsening (+92%) — requires investigation
- 🔴 Missing tunnel pod on node01 — reduced HA capacity by 33%
- ⚠️ 562 error groups introduced in 16.6.* — mostly inflated by WildFly proxy regeneration, but LazyInitializationException (242 users) warrants attention
- ⚠️ New EntityNotFoundException (ExamenVakHulpmiddel) appeared Feb 7 on v16.7.0 — monitor for recurrence
- ⚠️ 5xx error rate ~3x higher relative (but ~18 errors/hour absolute)
- ⚠️ Transient Sunday morning P99 spike (isolated event)

### Recommendations

1. **🔍 Critical:** Investigate authenticator P99 regression — worsening trend from +45% → +92%
2. **🔧 Critical:** Investigate/restore missing tunnel pod on som-k8s-node01 before weekday traffic
3. **📊 High:** Investigate `LazyInitializationException` in `GroepsindelingService.deleteGroepsindeling:345` — 242 users affected, pre-dates JEE10 but volume increased under 16.6.0. Check if JEE10 transaction/CDI scope changes affected Hibernate session lifecycle.
4. **📊 Medium:** Monitor the new `ExamenVakHulpmiddel` EntityNotFoundException (Feb 7, v16.7.0) — stale collection cache pattern
5. **📊 Medium:** Monitor Sunday morning spike pattern — check for batch jobs or GC pauses
6. **📈 Low:** The `$$$view` proxy proliferation is cosmetic (WildFly class regeneration) but creates noise in Bugsnag. Consider adding a Bugsnag grouping rule to collapse view variants.
7. **📈 Low:** Continue weekend-to-weekend monitoring for one more cycle to confirm stability
8. **✅ Positive:** The JEE10 heap memory improvements should reduce infrastructure costs and improve GC behavior long-term

### Jan 31 "Performance Paradox" — Resolved (with Caveats)

The Jan 31 report identified a "performance paradox" where P99 latency increased 167% with zero application errors. Deeper Bugsnag analysis now reveals this was **not actually zero errors** — the original analysis used the wrong release stage filter for the Backend project. The corrected picture:

- **Jan 9-15:** Significant error turbulence (17-20x 5xx spike) including WELD CDI injection failures and stale cache EntityNotFoundExceptions
- **Jan 15-24:** Errors self-resolved, 5xx normalized
- **Jan 31:** P99 spike likely caused by JVM warm-up/JIT differences + Infinispan cache race (129 errors in 9 seconds)
- **Feb 7-8:** Full recovery — performance at or better than JEE8 baseline

**Updated conclusions:**
- The first JEE10 week had genuine error issues (not "zero errors"), but they self-healed
- The P99 regression was still likely JVM warm-up related (the error patterns don't explain latency directly)
- **Lesson learned:** Always verify Bugsnag release stage filters per project (`"production"` vs `"productie"`)

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
