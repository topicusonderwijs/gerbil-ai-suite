# 🗄️ Database Research: System-wide 499 Errors Incident

**Investigation Time Window:** 08:00 - 14:00 CET (07:00 - 13:00 UTC)
**Datasources:** PgBouncer (pg-prod-w16, pg-prod-2ve, parro-db01)

## PgBouncer Client Active Connections (Total per Instance)

### pg-prod-w16

| Time (CET) | Time (UTC) | Active Connections | Status |
|------------|------------|-------------------|--------|
| 04:38 | 03:38 | 721 | ✅ Normal |
| 06:00 | 05:00 | ~1,000 | ✅ Normal |
| 07:00 | 06:00 | ~1,500 | ✅ Normal |
| 08:00 | 07:00 | ~1,900 | ⚠️ Elevated |
| 08:30 | 07:30 | ~2,500 | ⚠️ Elevated |
| 09:00 | 08:00 | ~2,976 | ⚠️ Elevated |
| 09:23 | 08:23 | 3,604 | 🔴 High |
| 09:48 | 08:48 | 3,891 - 4,297 | 🔴 Critical |
| 10:00 | 09:00 | ~4,463 | 🔴 Critical |
| 10:08 | 09:08 | ~4,362 | 🔴 Critical |
| 10:18 | 09:18 | ~4,320 | 🔴 Critical |
| 10:48 | 09:48 | **5,000** | 🔴 **LIMIT HIT** |
| 11:13 | 10:13 | **5,000** | 🔴 **LIMIT HIT** |
| 11:43 | 10:43 | **5,000** | 🔴 **LIMIT HIT** |
| 11:48 | 10:48 | **5,000** | 🔴 **LIMIT HIT** |
| 12:03 | 11:03 | **5,849** | 🔴 **OVER LIMIT** |
| 12:08 | 11:08 | 5,187 | 🔴 Critical |
| 12:48 | 11:48 | 2,623 | ⚠️ Recovering |
| 13:08 | 12:08 | 1,560 | ⚠️ Recovering |

### pg-prod-2ve

| Time (CET) | Time (UTC) | Active Connections | Status |
|------------|------------|-------------------|--------|
| 04:38 | 03:38 | 695 | ✅ Normal |
| 08:00 | 07:00 | ~1,500 | ✅ Normal |
| 09:00 | 08:00 | ~2,800 | ⚠️ Elevated |
| 09:23 | 08:23 | 3,662 | 🔴 High |
| 09:48 | 08:48 | ~3,900 | 🔴 Critical |
| 10:08 | 09:08 | ~4,395 | 🔴 Critical |
| 10:38 | 09:38 | ~4,670 | 🔴 Critical |
| 10:48 | 09:48 | **4,859 - 4,979** | 🔴 Near limit |
| 11:13 | 10:13 | **4,973** | 🔴 Near limit |
| 11:38-11:48 | 10:38-10:48 | 4,931 - **4,997** | 🔴 **LIMIT** |
| 12:03 | 11:03 | 4,214 | 🔴 Critical |
| 12:38 | 11:38 | 3,811 | 🔴 High |
| 12:58 | 11:58 | 1,843 | ⚠️ Recovering |
| 13:08 | 12:08 | 1,546 | ⚠️ Recovering |

## PgBouncer Client Waiting Connections

### pg-prod-w16 (🔴 CRITICAL — first waiting at incident onset)

| Time (CET) | Time (UTC) | Waiting Connections | Status |
|------------|------------|---------------------|--------|
| Before 09:50 | Before 08:50 | 0 | ✅ Normal |
| **09:50** | **08:50** | **2** | ⚠️ **INCIDENT START** |
| 09:55 | 08:55 | 18 | 🔴 Critical |
| 10:05 | 09:05 | 43 | 🔴 Critical |
| **10:10** | **09:10** | **86** | 🔴 **PEAK** |
| 10:25 | 09:25 | 20 | ⚠️ |
| 12:03 | 11:03 | 27 | ⚠️ |

### pg-prod-2ve (minor)

| Time (CET) | Time (UTC) | Waiting Connections | Status |
|------------|------------|---------------------|--------|
| 12:08 | 11:08 | 2 | ⚠️ |
| 13:03 | 12:03 | 1 | ⚠️ |

## PgBouncer Server Active Connections (Backend to PostgreSQL)

### pg-prod-w16

| Time (CET) | Time (UTC) | Server Active | Status |
|------------|------------|---------------|--------|
| 08:00 | 07:00 | ~5-10 | ✅ Normal |
| 09:00 | 08:00 | ~27 | ⚠️ Elevated |
| 09:18 | 08:18 | ~37 | ⚠️ Elevated |
| 09:23 | 08:23 | ~40 | ⚠️ Elevated |
| 09:28 | 08:28 | ~51 | 🔴 High |
| 09:33 | 08:33 | ~57 | 🔴 High |
| 09:38 | 08:38 | ~61 | 🔴 High |
| **09:52** | **08:52** | **366** | 🔴 **MASSIVE SPIKE** |
| 09:57 | 08:57 | 218 | 🔴 Critical |
| 10:02 | 09:02 | 188 | 🔴 Critical |
| 10:07 | 09:07 | 212 | 🔴 Critical |
| 10:40 | 09:40 | 279 | 🔴 Critical |
| 10:45 | 09:45 | 193 | 🔴 |
| 11:10 | 10:10 | 300 | 🔴 Critical |
| 12:08 | 11:08 | 193 | 🔴 |
| 12:38 | 11:38 | 93 | ⚠️ |
| 13:08 | 12:08 | 26 | ✅ Recovering |

### pg-prod-2ve

| Time (CET) | Time (UTC) | Server Active | Status |
|------------|------------|---------------|--------|
| 08:00 | 07:00 | ~5 | ✅ Normal |
| 09:00 | 08:00 | ~30 | ⚠️ |
| 10:00 | 09:00 | ~37 | ⚠️ |
| 10:28 | 09:28 | ~48 | ⚠️ |
| 10:48 | 09:48 | **226** | 🔴 Critical |
| 11:08 | 10:08 | **319** | 🔴 **PEAK** |
| 11:48 | 10:48 | **206** | 🔴 |
| 12:08 | 11:08 | 122 | 🔴 |
| 12:33 | 11:33 | ~100 | ⚠️ |
| 13:08 | 12:08 | 26 | ✅ Recovering |

## Client Active Connections by User (pg-prod-w16)

Top consumers at peak. These represent per-school/tenant database users:

| User | Max Connections | Peak Time (CET) | 08:00 | 09:00 | 09:50 | 10:00 |
|------|:-:|:-:|:-:|:-:|:-:|:-:|
| **landelijk_productie** | **629** | **09:02** | 25 | **629** | 310 | 493 |
| revolutionaryrunner_productie | 169 | 11:42 | 80 | 122 | 142 | 125 |
| consciousrhythm_productie | 165 | 10:42 | 82 | 110 | 113 | 94 |
| alertreflection_productie | 146 | 10:42 | 72 | 83 | 103 | 91 |
| digitalcupboard_productie | 138 | 10:42 | 59 | 76 | 90 | 86 |
| noblesuccess_productie | 137 | 11:42 | 68 | 95 | 106 | 116 |
| mainhabit_productie | 135 | 10:32 | 79 | 101 | 127 | 86 |

**Note:** `landelijk_productie` (sis-ui-landelijk component) consumed **629 connections** at 09:02 CET — abnormally high, 25x its baseline of ~25 connections. This occurred ~48 minutes before the main incident onset at 09:50 CET and may have been a precursor event.

## Queries Used

```promql
# Client active connections per instance
sum(pgbouncer_pools_client_active_connections{database="productie"}) by (instance)

# Client waiting connections per instance
sum(pgbouncer_pools_client_waiting_connections{database="productie"}) by (instance)

# Server active connections per instance
sum(pgbouncer_pools_server_active_connections{database="productie"}) by (instance)

# Client active connections by user (per-tenant breakdown)
sum(pgbouncer_pools_client_active_connections{database="productie"}) by (instance, user)
```

## Key Observations

- 🔴 **PgBouncer connection pool on both instances hit the 5,000 connection limit** starting around 10:48 CET, with pg-prod-w16 reaching 5,849 at 12:03 CET
- 🔴 **Waiting connections appeared on pg-prod-w16 at exactly 09:50 CET** — the exact moment the incident was reported, peaking at 86 waiting at 10:10 CET
- 🔴 **Server active connections spiked to 366 on pg-prod-w16 at 09:52 CET** — indicating long-running queries/transactions holding backend connections open
- ⚠️ **landelijk_productie user consumed 629 connections at 09:02 CET** — a precursor event that may have started stressing the connection pool before the main incident
- The connection counts show a gradual build-up throughout the morning (695→2976 by 09:00 CET) that accelerated into a crisis after 09:50 CET
- By 13:00 CET, connections are recovering to ~1,500-range levels
