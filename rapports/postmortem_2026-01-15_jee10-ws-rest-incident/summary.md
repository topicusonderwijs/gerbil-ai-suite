# 🔥 Postmortem Incident Report: JEE10 WS-REST Production Test

**Incident Date:** 15 januari 2026  
**Time Window:** 06:30 - 08:30 CET (05:30 - 07:30 UTC)  
**Affected Systems:** ws-rest, sis-ui, authenticator, inkijk-ws-rest, Traefik ingress  
**Severity:** 🔴 Critical (P1) - Volledige productie outage  

---

## 1. Executive Summary

Op 15 januari 2026 vond een productie-uitval plaats tijdens een gecontroleerde test van JEE10 migratie op ws-rest pods. De test verliep initieel goed (06:30-07:30), maar bij toenemende schoolbelasting cascadeerde het systeem in een volledige outage. 

**Root Cause:** JEE10's gewijzigde transaction handling en EJB view proxy gedrag veroorzaakte langlopende `idle_in_transaction` database connections. Dit leidde tot PgBouncer connection pool uitputting, Wildfly thread starvation, Traefik OOM, en uiteindelijk complete service unavailability.

**Resolution:** Snelle rollback naar JEE8 (~5 minuten) herstelde alle services volledig.

**Impact:** ~2 uur degraded service, waarvan ~45 minuten volledige outage. 117+ unieke gebruikers ervoeren login/authenticatie failures.

---

## 2. Timeline

| Tijd (CET) | Tijd (UTC) | Event | Severity |
|------------|------------|-------|----------|
| 06:30 | 05:30 | JEE10 deployment gestart op ws-rest pods | ℹ️ Info |
| 06:30-07:00 | 05:30-06:00 | Smooth operation, geen verhoogde load | ✅ Normal |
| 07:00 | 06:00 | Schooldag start, traffic stijgt | ✅ Normal |
| 07:30 | 06:30 | **Eerste signalen:** idle_in_tx connections stijgen (40-50) | ⚠️ Warning |
| 07:35 | 06:35 | **pg-prod-w16 waiting connections: 236** | 🔴 Critical |
| 07:36 | 06:36 | **P99 latency springt naar 5 seconden** | 🔴 Critical |
| 07:40 | 06:40 | Alle JEE10 pods bereiken **200% thread utilization** | 🔴 Critical |
| 07:40-07:45 | 06:40-06:45 | 502/504 errors escaleren, inkijk-ws-rest timeouts | 🔴 Critical |
| 07:55 | 06:55 | pg-prod-w16 waiting connections: **875** | 🔴 Critical |
| 08:00 | 07:00 | pg-prod-w16 waiting connections: **913 (PEAK)** | 🔴 Critical |
| 08:20 | 07:20 | **Traefik OOM** - 370/s 503 errors | 🔴 Critical |
| 08:20 | 07:20 | Cloudflare tunnel verliest backend | 🔴 Critical |
| 08:25 | 07:25 | Besluit: rollback naar JEE8 | ℹ️ Info |
| 08:30 | 07:30 | JEE8 rollback complete | ✅ Recovery |
| 08:35 | 07:35 | Services hersteld, errors normaliseren | ✅ Resolved |

---

## 3. Metrics Analysis

### 3.1 Database (PgBouncer & PostgreSQL)

| Metric | Baseline | During Incident | Peak | Recovery |
|--------|----------|-----------------|------|----------|
| PgBouncer Active (pg-prod-w16) | 900-1,200 | 2,500-3,600 | 3,600 | 4,000+ |
| PgBouncer Waiting (pg-prod-w16) | 0-2 | 200-900 | **913** 🔴 | 0-5 |
| PgBouncer Waiting (pg-prod-2ve) | 0-2 | 5-16 | 16 | 0-2 |
| idle_in_transaction | 5-15 | 100-320 | **320** 🔴 | 15-25 |
| Idle connections | 900-1,400 | 100-200 | **Drop to 100** 🔴 | 1,600+ |

**🚨 Kritieke bevinding:** pg-prod-w16 had **50-100x meer waiting connections** dan pg-prod-2ve. Dit wijst op asymmetrische load - mogelijk specifieke scholen/organisaties op w16.

### 3.2 Application (Wildfly & Traefik)

| Metric | Baseline | During Incident | Peak | Recovery |
|--------|----------|-----------------|------|----------|
| JEE10 Thread Utilization | 0-10% | 150-200% | **200%** 🔴 | N/A (rollback) |
| JEE8 Thread Utilization | 0-8% | 0-8% | 8% ✅ | 5-18% |
| Traefik P99 Latency | 0.6-0.8s | 5.0s | **5.0s** 🔴 (1hr+) | 0.5s |
| Request Rate | 2,000-3,000/s | 0-300/s | Drop to **0** 🔴 | 3,000/s |
| 5xx Error Rate | <0.1% | 5-50% | **>50%** 🔴 | <0.1% |

**🚨 Kritieke bevinding:** Alle JEE10 pods bereikten tegelijkertijd **200% thread utilization** (queue overflow), terwijl JEE8 pods stabiel bleven op 0-8%.

### 3.3 Error Distribution

| Error Code | Normal | During Incident | Peak | Cause |
|------------|--------|-----------------|------|-------|
| 502 Bad Gateway | 0/s | 5-50/s | 51.8/s | Backend pods overloaded |
| 503 Service Unavailable | 0/s | 0-370/s | **370/s** 🔴 | Traefik OOM |
| 504 Gateway Timeout | 0/s | 15-116/s | 116/s | DB connection timeouts |
| 500 Internal Error | <0.1/s | 0.1-2.6/s | 2.6/s | Application errors |

---

## 4. Root Cause Analysis

### 4.1 Confirmed Factors ✅

1. **JEE10 EJB View Proxy gedrag**
   - Nieuwe `$$$viewXXX` class patterns in Bugsnag errors
   - Verhoogde `StaleStateException` op `OAuth2TokenResourceService`
   - Transacties worden langer opengehouden dan in JEE8

2. **idle_in_transaction connection accumulation**
   - Stijging begon ~30 minuten vóór cascade (07:00-07:30)
   - Piek van 320 idle_in_tx connections
   - Directe oorzaak van connection pool exhaustion

3. **PgBouncer pool exhaustion**
   - 913 waiting connections op pg-prod-w16
   - Pool volledig uitgeput → applicatie threads geblokkeerd

4. **Cascade failure naar alle componenten**
   - ws-rest → Traefik → Cloudflare → complete outage

### 4.2 Probable Factors 🔶

1. **Infinispan cache disconnect**
   - Bewust losgekoppeld voor test
   - Mogelijk verhoogde database load door cache misses
   - Meer directe DB queries → meer connections nodig

2. **Asymmetrische load op pg-prod-w16**
   - 50-100x meer waiting connections dan pg-prod-2ve
   - Specifieke organisaties/scholen mogelijk geconcentreerd

3. **12 connections per schema limiet**
   - Met ~180-200 organisaties en piekbelasting
   - Mogelijk onvoldoende voor grote scholen (ASG?)

### 4.3 Cascade Failure Diagram

```
┌──────────────────────────────────────────────────────────────────────────────┐
│                          CASCADE FAILURE MECHANISM                           │
└──────────────────────────────────────────────────────────────────────────────┘

  ┌─────────────────────┐
  │  JEE10 Transaction  │  ← TRIGGER: Transaction handling houdt
  │  Handling Change    │    connections langer vast dan JEE8
  └──────────┬──────────┘
             │
             ▼
  ┌─────────────────────┐
  │  idle_in_tx ↑       │  07:00-07:30: Geleidelijke opbouw
  │  (10 → 320)         │
  └──────────┬──────────┘
             │
             ▼
  ┌─────────────────────┐
  │  PgBouncer Pool     │  07:35: Waiting connections exploderen
  │  Exhaustion         │  (913 op pg-prod-w16)
  └──────────┬──────────┘
             │
             ▼
  ┌─────────────────────┐
  │  Wildfly Thread     │  07:40: Alle threads wachten op DB
  │  Starvation (200%)  │  Queue overflow → kan geen requests verwerken
  └──────────┬──────────┘
             │
             ▼
  ┌─────────────────────┐
  │  Traefik Backlog    │  07:40-08:20: Requests bufferen op
  │  & Memory Growth    │  Latency → 5s+, memory groeit
  └──────────┬──────────┘
             │
             ▼
  ┌─────────────────────┐
  │  Traefik OOM        │  08:20: 370/s 503 errors
  │  (Out of Memory)    │  Complete frontend collapse
  └──────────┬──────────┘
             │
             ▼
  ┌─────────────────────┐
  │  Cloudflare Tunnel  │  08:20: Tunnel verliest backend
  │  Backend Lost       │  → Volledige outage voor end users
  └─────────────────────┘
```

---

## 5. Bugsnag Error Analysis

### 5.1 Top Errors During Incident

| Error | Events | Context | Analysis |
|-------|--------|---------|----------|
| `ConnectTimeoutException` (inkijk-ws-rest) | 2,852 | authenticator | Cascade naar andere services |
| `RollbackException` (StaleState) | 407 | rest | JEE10 EJB view proxy issues |
| `LazyInitializationException` | 28 | sis-ui | Session scoping issues |
| `ProcessingException` (Read timeout) | 31 | authenticator | OAuth service timeouts |
| `OptimisticLockException` | 40 | sis-ui, rest | Concurrent update conflicts |

### 5.2 Nieuwe JEE10-Specifieke Errors

| Error Pattern | First Seen | Evidence |
|---------------|------------|----------|
| `$$$view154` suffix in stack traces | Incident | JEE10 EJB view proxy |
| `$$$view146`, `$$$view151`, `$$$view152` | Incident | Multiple view proxies affected |
| `RLesRegistratieResourceImpl$$$view221` | Incident | REST resource views |

**Conclusie:** De `$$$viewXXX` patterns zijn **nieuw in JEE10** en wijzen op fundamenteel anders gedrag van EJB view proxies.

---

## 6. Data Gaps

De volgende metrics waren **niet beschikbaar** via Grafana queries:

| Metric | Impact | Alternative Evidence |
|--------|--------|---------------------|
| Container memory (ws-rest pods) | Kon OOM niet direct bevestigen | Thread utilization drops to 0% = restarts |
| Pod restart counts | Geen exact aantal restarts | Oscillatie 200%↔0% in threads |
| Cloudflare tunnel metrics | Tunnel status niet meetbaar | Indirect via 503 errors |
| CPU utilization per pod | Geen CPU correlatie | Thread metrics voldoende |

---

## 7. Conclusions

### 7.1 Confirmed ✅

1. **JEE10 transaction handling is fundamenteel anders** dan JEE8
2. **EJB view proxies in JEE10** houden database connections langer vast
3. **Connection pool sizing** is onvoldoende voor JEE10 gedrag
4. **Cascade failure** was voorspelbaar gegeven de resource constraints

### 7.2 Probable 🔶

1. **Infinispan disconnect** verergerde de situatie (meer DB load)
2. **ASG school** (genoemd in originele analyse) zat waarschijnlijk op pg-prod-w16
3. **12 connections per schema** is te weinig voor grote scholen met JEE10

### 7.3 Uncertain ❓

1. Exacte JEE10 configuratie verschil dat de langere transactions veroorzaakt
2. Of het probleem ook zou optreden MET Infinispan cache enabled
3. Rol van Zermelo API latency (circuit breaker actief, maar mogelijk bijdragend)

---

## 8. Recommendations

### 8.1 Immediate Actions (Pre-Volgende Test)

| # | Action | Priority | Owner |
|---|--------|----------|-------|
| 1 | Review JEE10 transaction timeout configuratie in standalone.xml | 🔴 High | Platform |
| 2 | Vergelijk EJB `@TransactionAttribute` defaults JEE8 vs JEE10 | 🔴 High | Development |
| 3 | Analyseer welke organisaties op pg-prod-w16 vs pg-prod-2ve zitten | 🔴 High | DBA |
| 4 | Verhoog PgBouncer pool size voor test environment | ⚠️ Medium | DBA |

### 8.2 Short-term Improvements (1-2 weken)

| # | Action | Priority | Owner |
|---|--------|----------|-------|
| 5 | Implementeer connection checkout timeout in datasource config | 🔴 High | Platform |
| 6 | Add alert: `waiting_connections > 50` | 🔴 High | SRE |
| 7 | Add alert: `idle_in_transaction > 50` | 🔴 High | SRE |
| 8 | Add alert: `thread_utilization > 80%` | 🔴 High | SRE |
| 9 | Load test JEE10 MET Infinispan enabled | ⚠️ Medium | QA |

### 8.3 Long-term Improvements (1-3 maanden)

| # | Action | Priority | Owner |
|---|--------|----------|-------|
| 10 | Implementeer circuit breaker voor DB connections | ⚠️ Medium | Development |
| 11 | Verhoog connections per schema van 12 naar 16-20 | ⚠️ Medium | DBA |
| 12 | Traefik memory limits verhogen + alerts | ⚠️ Medium | Platform |
| 13 | Custom readiness probe die thread pool health checkt | ⚠️ Medium | Development |
| 14 | Investigate horizontal sharding voor grote scholen | 🟡 Low | Architecture |

---

## 9. Appendix

### 9.1 Datasources Used

| Datasource | UID | Purpose |
|------------|-----|---------|
| Prometheus (Primary) | PBFA97CFB590B2093 | Infrastructure metrics |
| Grafana Cloud Metrics | RU1hwHA4k | Wildfly custom metrics |
| Bugsnag | 543ce4797765623fb900011d | Application errors |

### 9.2 Key Queries

```promql
# PgBouncer waiting connections
sum(pgbouncer_pools_client_waiting_connections{database="productie"}) by (instance)

# PostgreSQL connection states
sum(pg_stat_activity_count{datname="productie"}) by (state)

# Wildfly thread pool utilization
max((wildfly_io_busy_task_thread_count{kubernetes_cluster="somtoday"} 
  + wildfly_io_queue_size) / wildfly_io_max_pool_size) by (pod) * 100

# Traefik P99 latency
histogram_quantile(0.99, sum(irate(
  traefik_service_request_duration_seconds_bucket{kubernetes_cluster="somtoday"}[1m]
)) by (le))

# 5xx error rate by code
sum(rate(traefik_service_requests_total{kubernetes_cluster="somtoday", code=~"5.."}[1m])) by (code)
```

### 9.3 Research Files

Gedetailleerde analyse per domein beschikbaar in:
- [research/database.md](research/database.md) - PgBouncer & PostgreSQL analyse
- [research/application.md](research/application.md) - Wildfly & Traefik analyse
- [research/proxy.md](research/proxy.md) - Traefik ingress deep dive
- [research/exceptions.md](research/exceptions.md) - Bugsnag error analyse
- [research/kubernetes.md](research/kubernetes.md) - Pod health analyse
- [research/cloudflare.md](research/cloudflare.md) - Tunnel status (data gap)

---

## 10. Lessons Learned

### Wat ging goed 👍
- Snelle besluitvorming om terug te rollen (~5 minuten decision-to-recovery)
- JEE8 backup deployment was beschikbaar en klaar
- Team herkende het probleem snel

### Wat kan beter 👎
- Vroegere detectie van idle_in_tx buildup (30 min voor cascade)
- Betere load testing vóór productie test
- Infinispan niet tegelijk uitschakelen tijdens JEE10 test

### Unexpected Finding 🔍
De **asymmetrische load op pg-prod-w16** (913 vs 16 waiting connections) was niet verwacht en verdient nader onderzoek. Dit suggereert dat het probleem mogelijk geconcentreerd was bij specifieke organisaties/scholen.

---

*Postmortem gegenereerd: 2026-01-15*  
*Analyst: GitHub Copilot Incident Analyst*  
*Review status: Pending team review*
