# 🐛 Exceptions Research: System-wide 499 Errors / Connection Pool Saturation

**Investigation Time Window:** 08:00 - 14:00 CET (07:00 - 13:00 UTC)
**Sources:** Bugsnag (Backend, Docent, Leerling projects)

## Bugsnag Backend Errors (Somtoday — Project 543ce4797765623fb900011d)

**Filter:** `app.release_stage = "production"`, `event.since = 2026-03-09T07:00:00Z`, `event.before = 2026-03-09T14:00:00Z`

### Top Errors by Occurrence Count

| # | Error Class | Message (truncated) | Count (unthrottled) | First Seen (CET) | Component |
|---|------------|---------------------|:---:|:---:|-----------|
| 1 | **ConnectTimeoutException** | authenticator called rest-auth: Connect timeout | **155,908** | **09:01** | authenticator → rest-auth |
| 2 | **TimeoutException (Infinispan)** | ISPN000299: Unable to acquire lock after 15 seconds | **23,455** | **10:31** | docent-rest |
| 3 | EJBTransactionRolledbackException | Attempting to use a closed EntityManager | 12,037 | 08:32 | sis-ui |
| 4 | ConfigurationException | EjbInvocationResult: could not serialize ... docent-rest | 6,117 | 10:08 | docent-rest |
| 5 | NullPointerException | OverzichtService.handleRequest | 1,736 | 08:26 | sis-ui |
| 6 | EJBTransactionRolledbackException | Attempting concurrent modifications | 1,522 | 09:46 | sis-ui |
| 7 | InternalServerError (GraphQL) | Internal server error | 981 | 09:55 | general |
| 8 | UnknownHostException | prod-rest-auth: Temporary failure in name resolution | 894 | 09:16 | rest-auth DNS |
| 9 | ConnectTimeoutException | REST API connect timeout | 659 | 10:05 | general |
| 10 | EJBTransactionRolledbackException | RolledBack: various causes | 556 | 10:09 | general |

### Critical Error Analysis

#### 1. ConnectTimeoutException — authenticator → rest-auth (155,908 events)
- **First occurrence:** 09:01 CET (08:01 UTC) — **earliest significant error in the incident**
- **Significance:** The authenticator service could not connect to rest-auth. With 155,908 occurrences, this represents a massive failure rate.
- **Implication:** This may be the **root trigger** of the cascade. If rest-auth is unreachable, authentication fails, retries pile up, and connection pools saturate.
- **Correlation:** The landelijk_productie user (likely used by authenticator/rest-auth) spiked to 629 DB connections at 09:02 CET — just 1 minute after this error started.

#### 2. TimeoutException (Infinispan) — docent-rest (23,455 events)
- **First occurrence:** 10:31 CET (09:31 UTC)
- **Error:** `org.infinispan.util.concurrent.TimeoutException: ISPN000299: Unable to acquire lock after 15 seconds for key ...`
- **Significance:** Infinispan distributed cache coordination broke down between docent-rest pods. Pods could not respond to lock requests within 15s because they were overwhelmed with stuck requests.
- **Implication:** This is a **secondary failure** — caused by docent-rest thread exhaustion, not a cache infrastructure problem.

#### 3. EJBTransactionRolledbackException — sis-ui (12,037 events)
- **First occurrence:** 08:32 CET
- **Error:** "Attempting to use a closed EntityManager"
- **Significance:** Transaction timeouts causing premature EntityManager closure. Likely caused by DB connection pool starvation.

#### 4. ConfigurationException — docent-rest (6,117 events)
- **First occurrence:** 10:08 CET
- **Error:** "EjbInvocationResult: could not serialize"
- **Significance:** Serialization failures on docent-rest, likely related to Infinispan issues or overwhelmed JVMs.

#### 5. UnknownHostException — rest-auth DNS (894 events)
- **First occurrence:** 09:16 CET
- **Error:** "prod-rest-auth: Temporary failure in name resolution"
- **Significance:** DNS resolution for rest-auth failed under load. This indicates either DNS saturation or kube-dns issues, and explains why authenticator couldn't reach rest-auth.

### Error Timeline

```
08:26  NullPointerException in sis-ui OverzichtService (pre-existing, 1,736 events)
08:32  EJBTransactionRolledbackException in sis-ui (12,037 events — EntityManager)
09:01  ⚡ ConnectTimeoutException authenticator→rest-auth (155,908 events) ← EARLIEST
09:16  UnknownHostException for prod-rest-auth DNS (894 events)
09:46  EJBTransactionRolledbackException concurrent modifications (1,522 events)
09:55  GraphQL InternalServerError (981 events)
10:05  ConnectTimeoutException on REST API (659 events)
10:08  ConfigurationException serialization failures on docent-rest (6,117 events)
10:09  Additional EJBTransactionRolledbackExceptions (556 events)
10:31  ⚡ Infinispan TimeoutException on docent-rest (23,455 events) ← SECONDARY CASCADE
```

## Bugsnag Frontend Errors — Docent (Project 59d20374c943ea002679e025)

**Filter:** `app.release_stage = "productie"`, `event.since = 2026-03-09T07:00:00Z`, `event.before = 2026-03-09T14:00:00Z`

### Top Errors

| # | Error Class | Message | Count | First Seen (CET) |
|---|------------|---------|:---:|:---:|
| 1 | **FetchError** | request to https://api.somtoday.nl/rest/v1/docent/graphql failed, reason: connect ETIMEDOUT 10.244.x.x:443 | **5,836** | 09:53 |
| 2 | GraphQL Error | Schema mismatch: graphql changed while old schema loaded | 5,578 | 09:55 |
| 3 | FetchError | ETIMEDOUT to docent-rest pod 10.244.5.78:443 | 3,240 | 10:40 |
| 4 | FetchError | ETIMEDOUT to docent-rest pod 10.244.6.60:443 | 2,879 | 09:53 |
| 5 | FetchError | ETIMEDOUT to docent-rest pod 10.244.2.105:443 | 2,862 | 09:53 |
| 6 | FetchError | ETIMEDOUT to docent-rest pod 10.244.5.43:443 | 1,814 | 10:01 |
| 7 | FetchError | ETIMEDOUT to docent-rest pod 10.244.6.35:443 | 1,521 | 10:22 |
| 8 | FetchError | ETIMEDOUT to docent-rest pod 10.244.4.43:443 | 1,452 | 09:53 |
| 9 | FetchError | ETIMEDOUT to docent-rest pod 10.244.6.26:443 | 855 | 10:34 |
| 10 | FetchError | ETIMEDOUT to docent-rest pod 10.244.6.4:443 | 807 | 10:59 |

### Analysis

- **All timeouts target individual docent-rest pod IPs** — confirming that the docent-graphql frontend could not reach docent-rest backend pods
- **Multiple unique pod IPs affected** (10.244.5.78, 10.244.6.60, 10.244.2.105, 10.244.5.43, 10.244.6.35, 10.244.4.43, 10.244.6.26, 10.244.6.4) — this is ALL pods, not just one
- **First FetchError at 09:53 CET** — aligns with PgBouncer waiting connections appearing at 09:50 CET
- **Schema mismatch error** (5,578 events): GraphQL schema changed while old schema was loaded in the frontend. May indicate docent-rest pods becoming inconsistent as they struggle under load.

## Bugsnag Frontend Errors — Leerling (Project 65e09a58bf784d00154ac51a)

**Filter:** `app.release_stage = "productie"`, `event.since = 2026-03-09T07:00:00Z`, `event.before = 2026-03-09T14:00:00Z`

### Top Errors

| # | Error Class | Message | Count | First Seen (CET) |
|---|------------|---------|:---:|:---:|
| 1 | Error | Geen huidig account-profiel gevonden | 893 | 2025-09-17 (pre-existing) |
| 2 | HttpErrorResponse | 500 on /rest/v1/leerlingen/.../boodschappen | 79 | 2026-03-09 |
| 3 | HttpErrorResponse | Unknown Error on /rest/v1/leerlingen/.../vakkeuzes | 37 | 2025-10-14 (pre-existing) |
| 4-10 | Various | Various pre-existing errors | <30 each | Pre-existing |

### Analysis

- Leerling errors are **relatively mild** and mostly pre-existing
- The 500 errors on boodschappen endpoint (79 occurrences) are likely a secondary effect of the backend being overloaded
- The student-facing app was less affected than the teacher-facing app (docent)

## Cross-Source Correlation

| Time (CET) | Bugsnag Error | Prometheus Metric | Correlation |
|------------|---------------|-------------------|-------------|
| 09:01 | ConnectTimeoutException auth→rest-auth | landelijk_productie +629 connections | ✅ Authentication failures cause connection spike |
| 09:16 | UnknownHostException rest-auth DNS | — | DNS saturation under retry load |
| 09:50 | — | PgBouncer waiting connections appear | DB pool exhaustion begins |
| 09:53 | FetchError ETIMEDOUT docent-rest | docent-rest active users at 3,371 | ✅ Pods overwhelmed, not responding |
| 10:00 | — | System-wide P99 at 5.0s | All services hit timeout ceiling |
| 10:08 | ConfigurationException docent-rest | docent-rest active users at 13,577 | ✅ Pods can't serialize (overwhelmed) |
| 10:31 | Infinispan TimeoutException | PgBouncer active connections 4,500+ | ✅ Cache coordination fails under load |
| 12:38 | — | Peak error rates (499: 243/s) | Accumulation of all failures |

## Queries Used

```
# Bugsnag Backend
Project: 543ce4797765623fb900011d
Filter: app.release_stage = "production"
        event.since = 2026-03-09T07:00:00Z
        event.before = 2026-03-09T14:00:00Z

# Bugsnag Docent
Project: 59d20374c943ea002679e025
Filter: app.release_stage = "productie"
        event.since = 2026-03-09T07:00:00Z
        event.before = 2026-03-09T14:00:00Z

# Bugsnag Leerling
Project: 65e09a58bf784d00154ac51a
Filter: app.release_stage = "productie"
        event.since = 2026-03-09T07:00:00Z
        event.before = 2026-03-09T14:00:00Z
```

## Key Observations

- 🔴 **ConnectTimeoutException (auth→rest-auth) at 09:01 CET is the earliest significant error** with 155,908 occurrences — massive volume suggests a continuous failure, not a brief hiccup
- 🔴 **UnknownHostException at 09:16 CET** shows DNS resolution for rest-auth failed — this could indicate either DNS overload from retries, or rest-auth pods being unavailable
- 🔴 **Infinispan TimeoutException at 10:31 CET** (23,455 events) is a secondary cascade effect of docent-rest pod overload, not a primary cause
- 🔴 **All docent-rest pods affected** by ETIMEDOUT errors — not a single-pod issue
- ⚠️ **EJBTransactionRolledbackException at 08:32 CET** may be an early warning sign (EntityManager being closed), but with only 12K events and a common error type, it might be pre-existing
- The error timeline clearly supports the hypothesis that **rest-auth connectivity failure (09:01 CET) triggered a cascade** through DB connection pool saturation to system-wide service degradation
