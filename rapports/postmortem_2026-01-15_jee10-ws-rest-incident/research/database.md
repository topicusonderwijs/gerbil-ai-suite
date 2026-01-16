# 🗄️ Database Research: JEE10 WS-REST Incident

**Investigation Time Window:** 06:00 - 10:00 CET (05:00 - 09:00 UTC)
**Datasources:** PostgreSQL Exporters, PgBouncer

---

## Executive Summary

De database metrics bevestigen een catastrofale cascade failure. Het patroon toont:
1. **Baseline stabiliteit** (06:00-07:00 CET): Normale operatie
2. **Initiële stress** (07:00-07:30 CET): idle_in_transaction begint te stijgen
3. **Cascade failure** (07:30-08:30 CET): PgBouncer waiting connections exploderen
4. **Recovery** (08:30+ CET): Terugkeer naar JEE8, snel herstel

---

## PgBouncer Connection Pools

### Active Connections per Instance

| Timestamp (CET) | pg-prod-2ve | pg-prod-w16 | parro-db01 | Status |
|-----------------|-------------|-------------|------------|--------|
| 06:00 (baseline) | 1,200-1,600 | 900-1,200 | 50-80 | ✅ Normal |
| 06:30 | 1,000-1,400 | 1,000-1,400 | 60-100 | ✅ Normal |
| 07:00 | 1,400-1,800 | 1,400-1,800 | 80-120 | ✅ Normal (school start) |
| 07:30 | 2,500-3,500 | 2,500-3,600 | 100-150 | ⚠️ Elevated |
| 07:45-08:00 | **0-100 (drops!)** | **0-100 (drops!)** | 150-200 | 🔴 Critical - Connection failures |
| 08:15 | 2,000-2,500 | 2,000-2,500 | 100-150 | 🔴 Partial recovery attempts |
| 08:30 | 3,500-4,000 | 3,500-4,000 | 150-200 | ✅ Recovery begins |
| 09:00 | 4,000-4,500 | 4,000-4,500 | 200-250 | ✅ Stabilized |

**Observaties:**
- De actieve connecties toonden intermitterende drops naar 0-100, wat wijst op volledige connection pool uitputting
- pg-prod-2ve en pg-prod-w16 toonden identieke patronen - beide onder gelijke druk
- parro-db01 (Parro database) bleef stabiel door lagere load

### Waiting Connections (CRITICAL METRIC!)

| Timestamp (CET) | pg-prod-2ve | pg-prod-w16 | Status |
|-----------------|-------------|-------------|--------|
| 06:00-07:00 | 0-2 | 0-2 | ✅ Normal |
| 07:00-07:30 | 0-5 | 0-5 | ✅ Normal |
| 07:35 | 8 | **236** | 🔴 **CRITICAL START** |
| 07:40 | 12 | **538** | 🔴 CRITICAL |
| 07:45 | 10 | **582** | 🔴 CRITICAL |
| 07:50 | 16 | **574** | 🔴 CRITICAL |
| 07:55 | 6 | **875** | 🔴 CRITICAL |
| 08:00 | 8 | **913** | 🔴 **PEAK - Max backpressure** |
| 08:10 | 2 | **400-600** | 🔴 Still elevated |
| 08:30 | 0-2 | 0-5 | ✅ Recovery |

**🚨 KRITIEKE BEVINDING:**
- **pg-prod-w16 had DRAMATISCH hogere waiting connections dan pg-prod-2ve**
- Peak van **913 waiting connections** op pg-prod-w16 vs max ~16 op pg-prod-2ve
- Dit wijst op een **asymmetrische load** - mogelijk geconcentreerd op specifieke schema's/organisaties

---

## PostgreSQL Connection States

### idle_in_transaction Connections (Sum across all instances)

| Timestamp (CET) | Count | Status | Notes |
|-----------------|-------|--------|-------|
| 06:00 | 10-15 | ✅ Normal | Baseline |
| 06:30 | 5-10 | ✅ Normal | Pre-school |
| 07:00 | 10-20 | ✅ Normal | School start |
| 07:30 | 40-50 | ⚠️ Elevated | **First signs of trouble** |
| 07:40 | 60-80 | ⚠️ Elevated | Building up |
| 07:50 | 100-130 | 🔴 Critical | Rapid increase |
| 08:00 | 160-180 | 🔴 Critical | |
| 08:05 | **238** | 🔴 **PEAK** | Maximum idle_in_tx |
| 08:10 | 150-200 | 🔴 Critical | Oscillating |
| 08:15 | **270-320** | 🔴 **SECOND PEAK** | |
| 08:30 | 30-50 | ⚠️ Recovering | JEE8 rollback effect |
| 09:00 | 15-25 | ✅ Normal | Stabilized |

### Active Connections

| Timestamp (CET) | Count | Status |
|-----------------|-------|--------|
| 06:00-07:00 | 15-30 | ✅ Normal |
| 07:30-08:00 | 35-55 | ⚠️ Elevated |
| 08:00-08:30 | 60-120 | 🔴 Critical |
| 08:30+ | 60-100 | ✅ Normal (high traffic) |

### Idle Connections

| Timestamp (CET) | Count | Status | Notes |
|-----------------|-------|--------|-------|
| 06:00-07:00 | 400-700 | ✅ Normal | |
| 07:00-07:30 | 900-1,400 | ✅ Normal | Growing with traffic |
| 07:45 | **200-300** | 🔴 **Anomaly** | Drop indicates pool starvation |
| 08:00 | 100-150 | 🔴 Critical | Very low idle pool |
| 08:10 | 100-200 | 🔴 Critical | |
| 08:30 | 800-1,000 | ✅ Recovering | |
| 09:00 | 1,600-2,200 | ✅ Normal | Full recovery |

**Observaties:**
- Idle connections dropten van ~1,400 naar ~100-200 tijdens piek incident
- Dit betekent dat alle connections in gebruik waren of wachtten
- Correlatie: wanneer idle connections laag zijn, stijgen waiting connections exponentieel

---

## Cascade Pattern Analysis

```
Timeline (CET):

07:00 ┃ Normal operation, school day starts
      ┃
07:30 ┃ idle_in_tx begint te stijgen (→40-50)
      ┃ Dit wijst op langlopende transacties die niet commiten
      ┃
07:35 ┃ ⚡ TRIGGER POINT
      ┃ pg-prod-w16 waiting connections: 236 (eerste grote spike)
      ┃ pg-prod-2ve waiting: nog normaal (~8)
      ┃
07:40 ┃ 🔴 CASCADE BEGINT
      ┃ waiting connections pg-prod-w16: 538
      ┃ idle_in_tx: 60-80
      ┃ Threads beginnen vast te lopen wachtend op DB connections
      ┃
07:45-08:00 ┃ 🔴 VOLLEDIG INCIDENT
      ┃ waiting pg-prod-w16: 575-913
      ┃ idle_in_tx: 100-238
      ┃ Actieve connections drops naar 0 (pool exhausted)
      ┃ Traefik begint 502/504 errors te geven
      ┃
08:30 ┃ ✅ ROLLBACK TO JEE8
      ┃ idle_in_tx: drop naar 30-50
      ┃ waiting: terug naar 0-5
      ┃ idle pool: terug naar 800-1000
```

---

## Key Database Findings

### 1. **Asymmetric Load op pg-prod-w16**
- pg-prod-w16 had 50-100x meer waiting connections dan pg-prod-2ve
- Dit suggereert dat specifieke organisaties/schemas op w16 het probleem veroorzaakten
- **Aanbeveling**: Onderzoek welke organisaties op w16 zitten vs 2ve

### 2. **idle_in_transaction als Root Cause**
- De stijging van idle_in_tx begon ~30 minuten vóór de cascade
- Dit wijst op transacties die open blijven staan zonder commit/rollback
- Mogelijke oorzaken:
  - JEE10 transaction handling verschil
  - Connectie timeout configuratie
  - Lazy loading dat transacties open houdt

### 3. **Connection Pool Saturation Pattern**
```
idle_in_tx ↑ → idle connections ↓ → waiting ↑ → timeout → app threads blocked → OOM
```

### 4. **12 Connections per Schema Impact**
- Met ~180-200 organisaties en 12 connections per schema = ~2,160-2,400 max connections
- Tijdens piek: 3,500+ actieve connections nodig → pool kon dit niet aan
- **Mogelijke bottleneck**: te weinig connections per schema voor grote scholen

---

## Queries Used

```promql
# PgBouncer active connections
sum(pgbouncer_pools_client_active_connections{database="productie"}) by (instance)

# PgBouncer waiting connections
sum(pgbouncer_pools_client_waiting_connections{database="productie"}) by (instance)

# PostgreSQL connection states
sum(pg_stat_activity_count{datname="productie"}) by (state)

# Specific idle_in_transaction
sum(pg_stat_activity_count{datname="productie", state="idle in transaction"}) by (instance)
```

---

## Recommendations

1. **Investigate pg-prod-w16 specifically**
   - Welke scholen/organisaties zitten op deze database instance?
   - Correlatie met ASG school (vermeld in originele postmortem)

2. **Transaction timeout configuration**
   - JEE10 gebruikt mogelijk andere defaults voor transaction timeouts
   - Vergelijk met JEE8 configuratie

3. **Connection pool monitoring alerts**
   - Alert wanneer waiting connections > 50
   - Alert wanneer idle_in_tx > 50

4. **PgBouncer pool_mode verificatie**
   - Check of `transaction` mode correct werkt met JEE10
   - Overweeg `statement` mode voor korte queries

---

*Research verzameld: 2026-01-15*
*Analyst: GitHub Copilot Incident Analyst*
