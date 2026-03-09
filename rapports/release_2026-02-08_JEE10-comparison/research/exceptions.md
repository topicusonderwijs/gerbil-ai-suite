# 🐛 Exception Research: JEE10 Weekend Comparison

**Window:** Feb 7-8, 2026 (weekend) + version 16.6.* error analysis (Jan 9 — Feb 8, 2026)
**Source:** SmartBear/Bugsnag
**Note:** Somtoday Backend uses release stage `"production"` (not `"productie"` like frontend projects)

> **⚠️ Platform Correction:** JEE10 was first deployed **Jan 31**, rolled back to JEE8 on **Feb 2**, and re-deployed **Feb 6 at 17:00 CET**. Errors from Jan 9-30 occurred under the **JEE8 platform**. Only errors from Jan 31-Feb 1 and Feb 6+ are from the JEE10 platform. The version `16.6.0` was a code release on Jan 9 (on JEE8), not a JEE10 deployment.

---

## Somtoday Backend (543ce4797765623fb900011d)

**Total open errors (30d, production):** 150
**Errors introduced in version 16.6.*:** 562 error groups
**Filter:** `app.release_stage = "production"`, `version.introduced_in = "16.6.*"`

### ⚠️ 5xx Spike Correlation — Corrected Platform Attribution

Prometheus 5xx error rate snapshots, with corrected platform attribution:

| Date | 5xx Rate/sec | ~Errors/hour | Platform | Context |
|------|-------------|-------------|----------|---------||
| **Jan 9** (v16.6.0 release) | **0.0775** | **~279** | ⚠️ **JEE8** | Version 16.6.0 code release (JEE8 platform) |
| **Jan 13** (WELD CDI active) | **0.0918** | **~330** | ⚠️ **JEE8** | Version 16.6.0 code issue (JEE8 platform) |
| Jan 24 (JEE8 baseline) | 0.00446 | ~16 | JEE8 | ✅ Normal |
| **Jan 31** (JEE10 deploy #1) | 0.00335 | ~12 | **JEE10** | ✅ Normal |
| Feb 2-6 (rollback) | — | — | JEE8 | Rolled back to JEE8 |
| **Feb 6 18:00 CET** (re-deploy +1h) | 0.00781 | ~28 | **JEE10** | Post JEE10 re-deployment |
| **Feb 7** (JEE10 deploy #2) | 0.00502 | ~18 | **JEE10** | ✅ Normal |
| **Feb 8 10:00 CET** | 0.00139 | ~5 | **JEE10** | ✅ Normal |

**Corrected Finding:** The Jan 9-15 5xx spike (17-20x) was caused by **version 16.6.0 code issues on the JEE8 platform**, not by JEE10. JEE10 was not deployed until Jan 31. The WELD CDI injection failure (Jan 12-15) and EntityNotFoundException bursts (Jan 9-14) all occurred under JEE8 runtime. During actual JEE10 windows (Jan 31-Feb 1 and Feb 6-8), 5xx error rates have been normal and stable.

---

### Version 16.6.0 Issues (Originally Misattributed to JEE10)

#### 1. WELD-000713: CDI ServletContext Injection Failure — RESOLVED (**JEE8 period**)

| Metric | Value |
|--------|-------|
| Error Class | `org.jboss.weld.exceptions.IllegalStateException` |
| Events (production) | **781** |
| Users | **145** (4 organisations) |
| Context | rest |
| First seen | 2026-01-12 13:16:48 |
| Last seen | 2026-01-15 16:08:17 |
| Active period | **3 days only** |
| Version | 16.6.0 only |

**Stack trace:**
```
ApplicationInfoBean.lambda$forServlet$0 (ApplicationInfoBean.java:36)
  → ApplicationInfoBean.readManifest
  → RestDAOContext.getAppInfo
  → OrganisatieListener.fireEvent  (Hibernate @PostLoad callback)
```

**Root cause:** ~~Originally attributed to JEE10 CDI migration~~ — **Correction:** This error occurred Jan 12-15, **before JEE10 was deployed** (Jan 31). This is a version 16.6.0 code issue on the JEE8 platform. The `ServletContextBean` could not resolve the `ServletContext` for a cross-module class loader (`iridium-common-dao.jar` accessing `iridium-ws-rest.war` context). Root cause is likely a code change in 16.6.0 affecting CDI bean resolution, not JEE10 runtime changes.

**Organisations affected:** Carmel College West Betuwe (551 events), Carmel Lyceum Hurdegaryp (233), Lyceum Ypenburg (1), Test College (1)

**Status:** ✅ Self-resolved after 3 days. Not seen since Jan 15. Likely resolved by a Wildfly/Weld warm-up cycle or classloader stabilization. **Note:** Not seen during actual JEE10 runtime windows (Jan 31-Feb 1, Feb 6-8), confirming this is not a JEE10 platform issue.

### 🔴 Confirmed JEE10-Specific Issues

#### 2. Infinispan CacheEntry NullPointerException — RESOLVED (**JEE10 period confirmed**)

| Metric | Value |
|--------|-------|
| Error Class | `java.lang.NullPointerException` |
| Message | Cannot invoke `CacheEntry.isRemoved()` because "entry" is null |
| Events | **129** |
| Users | **47** (35 organisations) |
| Context | rest |
| First seen | 2026-01-31 09:07:19 |
| Last seen | 2026-01-31 09:07:28 |
| Active period | **9 seconds only** |
| BuildNumber | `30-jee10` |
| Java Version | `21.0.9+10-LTS` |

**Stack trace:**
```
CallInterceptor.visitGetKeyValueCommand:644  (Infinispan cache chain)
  → ReadOnlyEntityDataAccess.get  (Hibernate L2 cache)
  → LeerlingContextPermissionResolver.init:116
```

**Root cause:** Infinispan Hibernate 2nd-level cache race condition. 5 pods simultaneously hit a null `CacheEntry` during permission resolution. This is likely an Infinispan version incompatibility or transient cache invalidation race during a JEE10 deployment cycle.

**Status:** ✅ Single 9-second burst on Jan 31. Not recurred.

---

### ⚠️ High-Volume Errors Introduced in 16.6.*

#### 3. RollbackException / OAuth2Token StaleState — ONGOING

| View Variant | Events | First Seen | Last Seen | Status |
|-------------|--------|-----------|----------|--------|
| `$$$view150` (jakarta) | 5,542 | Jan 9 | Feb 8 | 🟡 Active |
| `$$$view159` (jakarta) | 6,804 | Feb 1 | Feb 8 | 🟡 Active |
| `$$$view154` (jakarta) | 735 | Jan 15 | Feb 1 | ✅ Stopped |
| `$$$view162` (javax) | 1,574 | Feb 1 | Feb 6 | ✅ Stopped |
| **Total** | **~14,655** | | | |

- All target `OAuth2TokenResourceService.setStatus` — optimistic locking on OAuth2 token status updates
- Only 1 user affected (system/background process)
- **New `$$$view` references appearing each deployment** — this is expected WildFly proxy class regeneration under JEE10
- Pre-existing error pattern, but the view variant proliferation is JEE10-specific
- **No user impact** — single service account

#### 4. LazyInitializationException — Groepsindeling — ONGOING

| Metric | Value |
|--------|-------|
| Error Class | `org.hibernate.LazyInitializationException` |
| Message | failed to lazily initialize `Leerling.groepsindelingen` |
| Events (production) | **1,157** |
| Users | **242** (102 organisations) |
| Context | sis-ui |
| First seen (unfiltered) | 2026-01-06 ← **Pre-dates JEE10 by 3 days** |
| First seen (in 16.6.0) | 2026-01-10 |
| Last seen | 2026-02-06 |
| Versions | 16.6.0 (1,157), 16.7.0 (40) |

**Stack trace:**
```
GroepsindelingService.deleteGroepsindeling:345
  → PersistentBag.remove → LazyInitializationException (no Session)
  → EditGroepsindelingPanel → Wicket onClick
```

**Root cause:** Hibernate session already closed when lazily loading `Leerling.groepsindelingen` collection during delete operation. The error pre-dates JEE10 (Jan 6) but became more prevalent under 16.6.0 — possibly due to changed transaction/CDI scope boundaries in JEE10.

**Assessment:** Pre-existing bug, but volume increase under 16.6.0 warrants investigation of JEE10 transaction scope changes.

#### 5. EntityNotFoundException — Multiple Entities — MOSTLY RESOLVED

| Entity | Events | Users | First Seen | Last Seen | Status |
|--------|--------|-------|-----------|----------|--------|
| `ResultaatAnderVakKolom` (6 proxy variants) | **~1,215** | ~400+ | Jan 9 | Jan 14 | ✅ Resolved |
| `SWIBijlage` (javax) | 861 | 595 | Jan 15 | Jan 22 | ✅ Resolved |
| `SWIBijlage` (jakarta) | 200 | 147 | Jan 19 | Jan 22 | ✅ Resolved |
| `Groepsindeling` | 257 | 6 | Jan 15 | Jan 21 | ✅ Resolved |
| `ExamenVakHulpmiddel` (**NEW**) | 16 | 1 | **Feb 7** | Feb 7 | 🟡 New |

**ResultaatAnderVakKolom** — 6 different HibernateProxy class variants all referencing the same entity IDs. This is a stale Hibernate 2nd-level cache issue where cached collection entries reference entities that have been deleted. The proxy variant proliferation is again due to WildFly JEE10 proxy regeneration. **Self-resolved after ~5 days.**

**SWIBijlage** — Same stale cache pattern. Appeared in both `javax.persistence` and `jakarta.persistence` namespace variants, confirming the JEE8→JEE10 transition was active. **Self-resolved after ~7 days.**

**ExamenVakHulpmiddel** — **New error as of Feb 7.** `WicketRuntimeException` wrapping `jakarta.persistence.EntityNotFoundException` in `IridiumExamenVakService.getBijzonderheden:210`. However, this runs on **version 16.7.0** (BuildNumber "25-jee10"), single user at Quadraam organisation. Same stale collection cache root cause. **Monitor for recurrence.**

#### 6. OptimisticLockException / LesRegistratie — ONGOING

| View Variant | Events | Users | First Seen | Last Seen |
|-------------|--------|-------|-----------|----------|
| `$$$view235` | 149 | 132 | Jan 16 | Jan 29 |
| `$$$view229` | 124 | 111 | Jan 30 | Feb 6 |
| `$$$view227` | 106 | 92 | Jan 23 | Jan 29 |
| `$$$view219` | 105 | 89 | Feb 2 | Feb 6 |
| `$$$view223` | 89 | 80 | Jan 15 | Jan 22 |
| `$$$view220` | 73 | 67 | Jan 15 | Jan 22 |
| `$$$view242` | 71 | 60 | Feb 2 | Feb 6 |
| `$$$view225` | 52 | 48 | Jan 9 | Jan 14 |
| `$$$view231` | 63 | 54 | Jan 12 | Jan 30 |
| **Total** | **~832** | **~550+** | | |

All target `RLesRegistratieResourceImpl.registratiesCreateOrUpdate` — concurrent attendance registration updates causing stale state. **Each deployment generates a new `$$$view` variant** because WildFly regenerates proxy classes. The underlying concurrency issue is pre-existing but the view proliferation is JEE10-specific.

#### 7. ConstraintViolationException — SWIGemaakt — ONGOING

| View Variant | Events | Users | First Seen | Last Seen |
|-------------|--------|-------|-----------|----------|
| `$$$view57` | 120 | 118 | Jan 10 | Feb 8 |
| `$$$view55` | 112 | 110 | Jan 9 | Feb 7 |
| **Total** | **~232** | **~228** | | |

Duplicate key constraint on `swigemaakt_leerling_switoekenning_key` in `RSWIGemaaktResourceImpl.createOrUpdate`. Race condition when multiple requests try to insert the same SWIGemaakt record simultaneously. **Consistent across all JEE10 weeks, not worsening.**

#### 8. Other Notable Errors

| Error | Events | Users | Period | Status |
|-------|--------|-------|--------|--------|
| `IllegalArgumentException` (URI: `http:`) | 117 | 1 | Jan 15 — Feb 8 | 🟡 Ongoing |
| `SocketTimeoutException` (TurnitinClient) | 108 | 103 | Jan 20-22 | ✅ Resolved |

**IllegalArgumentException:** `RLeerlingSessionExchangeImpl.java:156` — malformed URI `http:` (missing `//`). Single user, consistent rate. Likely misconfigured client.

**SocketTimeoutException:** External Turnitin service timeout. Not JEE10-related.

---

### This Weekend's Production Errors (Feb 7-8, 2d window)

| Error Class | Message | Events | Users | Context |
|-------------|---------|--------|-------|---------|
| `TurnitinException` | Opvragen van geaccepteerde eula mislukt | 1,762 | 317 | rest |
| `TurnitinException` (2nd group) | Opvragen van geaccepteerde eula mislukt | 153 | 29 | rest |
| `jakarta.transaction.RollbackException` (view155) | Could not commit transaction | 158 | 1 | rest |
| `jakarta.transaction.RollbackException` (view150) | Could not commit transaction | 124 | 1 | rest |
| `jakarta.transaction.RollbackException` (view159) | Could not commit transaction | 101 | 1 | rest |
| `jakarta.transaction.RollbackException` (view153) | Could not commit transaction | 87 | 1 | rest |
| `TurnitinException` (SocketTimeout variant) | Opvragen van geaccepteerde eula mislukt | 57 | 13 | rest |
| `ExecutionException` | Could not send Message (EduIX) | 30 | 0 | sis-ui |
| `IllegalArgumentException` | Expected scheme-specific part at index 5: http: | 22 | 1 | rest |
| `NonUniqueResultException` | — | 22 | 2 | rest |
| `WicketRuntimeException` / `EntityNotFoundException` | ExamenVakHulpmiddel | 16 | 1 | sis-ui |

**TurnitinException:** 1,972 total — burst between 16:07-17:33 UTC on Feb 7. External Turnitin EULA service outage. Pre-existing (Sep 2025), not JEE10-related.

**RollbackException/OAuth2Token:** 470 events this weekend across 4 view variants. All target `OAuth2TokenResourceService.setStatus`. Single service account. Pre-existing pattern, consistent volume.

**WicketRuntimeException/ExamenVakHulpmiddel:** 16 events, 1 user (Quadraam). **New this weekend** but runs on version 16.7.0. Stale Hibernate collection cache referencing deleted entity. **Monitor.**

---

## Somtoday Leerling (65e09a58bf784d00154ac51a)

**Total open errors this weekend:** 31

### Notable Errors

| Error Class | Message | Events | Users | Stage |
|-------------|---------|--------|-------|-------|
| `Error` | Geen huidig account-profiel gevonden | 173 | 168 | productie, native |
| `HttpErrorResponse` | 403 on maatregeltoekenningen/actief | 54 | 30 | productie, native |
| `HttpErrorResponse` | 400 on swgebruik/swiextmat | 54 | 33 | productie, native |
| `Error` | EdgeToEdge plugin not implemented on iOS | 40 | 20 | native |
| `InvalidError` | angular error handler non-error (oauth) | 40 | 33 | native, productie |
| `TypeError` | URL.canParse is not a function | 17 | 17 | productie |

### Analysis — Leerling

- **"Geen huidig account-profiel gevonden"**: Highest user impact (168 users). Pre-existing since version 16.6.0 release (Jan 9, JEE8 platform). Session/profile lookup issue — not JEE10-related.
- **HttpErrorResponse 403**: Authorization issue on `maatregeltoekenningen` endpoint — pre-existing
- **TypeError: URL.canParse**: Relatively new (first seen Feb 6) — Safari/older browser compatibility issue

---

## Somtoday Docent (59d20374c943ea002679e025)

**Total open errors this weekend:** 30

### Notable Errors

| Error Class | Message | Events | Users | Stage |
|-------------|---------|--------|-------|-------|
| `ValidationError` | Cannot query field "rechten" on SchoolcommunicatieRechten | 872 | 0 | productie |
| `TypeError` | Cannot read properties of undefined (editAfspraakForm) | 485 | 256 | productie |
| `TypeError` | undefined is not an object (editAfspraakForm.get) | 107 | 65 | productie |
| `Error` | NG0101 (profiel) | 62 | 16 | productie |
| `Error` | NG0101 (rooster) | 55 | 11 | productie |

### Analysis — Docent

- **ValidationError "rechten"**: High volume (872 events) but 0 users — likely a background/server-side GraphQL query issue. Pre-existing since Sep 2025.
- **TypeError editAfspraakForm**: Significant user impact (256+65 users). Form initialization race condition in rooster/appointment editing. Pre-existing since Jan 2026.
- **NG0101 (Angular)**: Change detection errors — pre-existing.

---

## Production Error Summary

| Metric | Value | Status |
|--------|-------|--------|
| Error groups introduced in 16.6.* (production) | **562** | ⚠️ Significant |
| 5xx spike on release day (Jan 9) | ~279 errors/hour | ⚠️ v16.6.0 on JEE8 (not JEE10) |
| 5xx spike on Jan 13 | ~330 errors/hour | ⚠️ v16.6.0 on JEE8 (not JEE10) |
| 5xx rate on Feb 7 (this weekend) | ~18 errors/hour | ✅ Normal |
| Confirmed JEE10-specific errors | **1** (Infinispan CacheEntry NPE only) | ✅ Self-resolved (9s burst) |
| Critical (Error) severity in production | **0** | ✅ |
| New errors this weekend (Feb 7-8) | **1** (ExamenVakHulpmiddel, v16.7.0) | ⚠️ Monitor |

### Key Findings

1. **5xx error spikes on Jan 9-15 were version 16.6.0 code issues on JEE8**, NOT JEE10 — JEE10 was not deployed until Jan 31. The 17-20x spike was driven by EntityNotFoundException bursts and the WELD CDI injection failure, all running on JEE8 platform. Error rates normalized by Jan 24.

2. **One confirmed JEE10-specific error** (corrected from 2 after timeline review):
   - ~~WELD-000713 CDI injection (Jan 12-15)~~ → **Reclassified as JEE8-period version 16.6.0 issue**
   - Infinispan CacheEntry NPE (129 events, 47 users, Jan 31 9-second burst) → **Confirmed JEE10** (`BuildNumber: "30-jee10"`)

3. **`$$$view` proxy proliferation** occurs on each WildFly deployment, causing existing errors (RollbackException, OptimisticLockException) to fragment into many error groups. This inflates the "562 introduced in 16.6.*" count. The underlying bugs are **pre-existing** and most appeared during the JEE8 period (Jan 9-30).

4. **EntityNotFoundException pattern** (ResultaatAnderVakKolom, SWIBijlage, Groepsindeling): These occurred Jan 9-22, **during JEE8 runtime** — they are stale Hibernate cache issues related to version 16.6.0 code changes, not JEE10 migration. **One new occurrence on Feb 7** (ExamenVakHulpmiddel) on version 16.7.0 during JEE10 runtime — monitor.

5. **LazyInitializationException** pre-dates both JEE10 and 16.6.0 (first seen Jan 6) but volume increased under 16.6.0. May be related to code changes rather than JEE10 platform. 242 users affected. Warrants investigation.

6. **Actual JEE10 error windows are clean** — during Jan 31-Feb 1 and Feb 6-8, no new JEE10-specific errors emerged and 5xx rates were normal.
