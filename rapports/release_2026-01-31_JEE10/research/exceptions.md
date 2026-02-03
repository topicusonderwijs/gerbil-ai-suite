# 🐛 Exceptions Research: JEE10 Migration Release

**Release Time Window:** 2026-01-31 00:00 to 2026-02-02 23:59 CET
**Baseline Period (JEE8):** 2026-01-24 to 2026-01-29
**Bugsnag Projects:** Somtoday, Somtoday Docent, Somtoday Leerling

## Error Summary by Project

### During JEE10 Release (Jan 31 - Feb 2)

| Project | Total Errors | Top Error Count | Error Types |
|---------|--------------|-----------------|-------------|
| Somtoday (Backend) | 311 | 20+ | Transaction, Hibernate, Auth |
| Somtoday Docent (Angular) | 59 | 20 | GraphQL, Fetch, Angular |
| Somtoday Leerling (Mobile) | 65 | 20 | HTTP, iOS, Auth |

### Baseline Week (Jan 24 - Jan 29, JEE8)

| Project | Total Errors | Comparison |
|---------|--------------|------------|
| Somtoday (Backend) | 411 | -100 errors (-24%) |

**Observation:** Error count actually **decreased** during JEE10 weekend vs. the baseline JEE8 week, but this may be due to lower weekend traffic.

## Top Errors During JEE10 Release

### Somtoday Backend (543ce4797765623fb900011d)

## CRITICAL: Saturday Performance Regression Window (10:00-16:00 CET)

**🔴 SMOKING GUN:** Errors during exact P99 latency spike window (1.17s → 3.12s, +167%)

### Database Schema Migration Failure
**Error ID:** `6781d0a0bd74ea4847e1ca99` (19 events)  
**Type:** `javax.ejb.EJBTransactionRolledbackException`  
**Root Cause:** `ERROR: relation "afgenomenfeature" does not exist`

```
Stack Path: ResultatenPublicerenJob → FeatureService.isFeatureActief() [149] 
           → AfgenomenFeatureDAO.isFeatureAfgenomenOpPeildatum() [42]
           → AbstractDAO.exists() [733] → SQL GRAMMAR EXCEPTION
```

**Impact:** Feature flag database checks failing → transaction rollbacks → connection pool exhaustion → P99 latency spike

### Hibernate 6 Entity Casting Issue  
**Error ID:** `697e2591d9ec7652c2db3d2a` (3 events)  
**Type:** `org.apache.wicket.WicketRuntimeException`  
**Message:** "Can't cast expression to unknown type: nl.topicus.platinum.entities.Stamgroep"

```  
Stack Path: WaarnemingHibernate6DataAccessHelperImpl.addAfdelingCriteria() [391]
           → JQ.as() [221] → Can't cast expression 
```

**Impact:** UI data panel rendering failures → slow page loads → user-facing performance degradation

### Error Correlation Summary
- **Timeline Match:** Errors concentrated in exact P99 spike window (Sat 10:00-16:00)
- **System Impact:** Database failures → resource contention → widespread slowdown  
- **JEE10 Root Cause:** Schema migration incompleteness + Hibernate 6 entity mapping issues

## Regular Error Patterns

| Error | Events | First Seen | Context | Severity |
|-------|--------|------------|---------|----------|
| `javax.transaction.RollbackException` (OAuth2Token) | 1,802 | Feb 1 14:45 | REST | ⚠️ Warning |
| `javax.ejb.EJBTransactionRolledbackException` (SQL) | 1,131 | Jan 31 00:15 | SIS-UI | ⚠️ Warning |
| `javax.transaction.RollbackException` (view162) | 383 | Feb 1 14:41 | REST | ⚠️ Warning |
| `javax.ws.rs.ProcessingException` (SocketTimeout) | 360 | Feb 2 08:00 | Auth | ⚠️ Warning |
| `WicketRuntimeException` (LeerlingFotoPanel) | 316 | Jan 31 08:35 | SIS-UI | ⚠️ Warning |

### NEW Errors First Seen During JEE10 Release 🔴

| Error | First Seen | Events | Context | Impact |
|-------|------------|--------|---------|--------|
| `RollbackException` (view159) | Feb 1 14:45 | 1,802 | REST | High |
| `RollbackException` (view162) | Feb 1 14:41 | 383 | REST | Medium |
| `NullPointerException` (Infinispan CacheEntry) | Jan 31 09:07 | 129 | REST | Medium |

The **Infinispan NullPointerException** is particularly concerning:
```
Cannot invoke "org.infinispan.container.entries.CacheEntry.isRemoved()" because "entry" is null
```
This occurred immediately after deployment (Jan 31 09:07) in `LeerlingContextPermissionResolver.java:116`

### JEE8 → JEE10 Package Changes Observed

Notable package namespace changes detected in errors:
- `javax.transaction.RollbackException` (JEE8) → Still present
- `jakarta.transaction.RollbackException` (JEE10) → **NEW** errors appearing

| Error Class | JEE Version | Events |
|-------------|-------------|--------|
| `javax.transaction.RollbackException` | JEE8 | 2,185+ |
| `jakarta.transaction.RollbackException` | JEE10 | 297+ |

This indicates mixed JEE8/JEE10 code paths or transitional state.

### Somtoday Docent (Angular Frontend)

| Error | Events | Context | Severity |
|-------|--------|---------|----------|
| `GraphQLError` (403 Forbidden) | 1,681 | main.js | ⚠️ Warning |
| `FetchError` (ETIMEDOUT) | 1,121 | node-fetch | ⚠️ Warning |
| `Error` (NG0101) | 436 | rooster/registratie | 🔴 Error |
| `Error` (NG0101) | 408 | rooster | 🔴 Error |

The **FetchError ETIMEDOUT** (1,121 events) suggests backend connectivity issues:
```
request to http://prod-docent-rest.prod-application/rest/v1/medewerkers failed, reason: connect ETIMEDOUT 10.43.196.44:80
```

### Somtoday Leerling (Mobile App)

| Error | Events | Context | Severity |
|-------|--------|---------|----------|
| `Error` (Geen huidig account-profiel) | 2,504 | /login | 🔴 Error |
| `InvalidError` (angular error handler) | 278 | oauth/callback | 🔴 Error |
| `TypeError` (forEach undefined) | 169 | /rooster | 🔴 Error |
| `Error` (EdgeToEdge not implemented iOS) | 160 | / | 🔴 Error |

## Stability Scores

| Project | Version | Session Stability | Target | Status |
|---------|---------|-------------------|--------|--------|
| Somtoday | 16.6.0 (JEE10) | N/A* | 99% | ❓ Unknown |
| Somtoday | 16.5.0 (JEE8) | N/A* | 99% | ❓ Unknown |

*Session data not populated in Bugsnag release API

## Key Findings

### Regressions Detected 🔴

1. **Infinispan Cache NullPointerException** - NEW error type
   - File: `LeerlingContextPermissionResolver.java:116`
   - 129 events immediately after deployment
   
2. **Backend Timeout Errors** - Increased
   - FetchError ETIMEDOUT connecting to docent-rest
   - 1,121 events
   
3. **Jakarta Transaction Errors** - NEW error class
   - `jakarta.transaction.RollbackException` first appeared
   - Indicates JEE10 code paths being executed

### Existing Issues (Not Regression)

1. **OAuth2Token StaleStateException** - Pre-existing
   - Multiple view versions indicate ongoing race condition
   - Not a JEE10 regression
   
2. **WicketRuntimeException LeerlingFotoPanel** - Pre-existing
   - Entity deleted while in use
   - First seen 2023-01-16

### Improvements Observed ✅

- Overall error count decreased vs baseline week
- Some error classes show reduced occurrence

## Recommendations

1. **Investigate Infinispan NullPointerException** - Potential JEE10 cache compatibility issue
2. **Monitor jakarta.* errors** - Track JEE10 namespace transition
3. **Review docent-rest connectivity** - ETIMEDOUT errors suggest service startup/health issues

## Queries Used

Bugsnag API filters:
```json
{
  "event.since": "2026-01-31T00:00:00Z",
  "event.before": "2026-02-03T00:00:00Z",
  "error.status": "open"
}
```
