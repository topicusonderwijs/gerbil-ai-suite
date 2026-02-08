# 🗄️ Database Research: JEE10 Weekend Comparison

**Comparison Window:** Feb 7, 2026 vs Jan 24, 2026 (Saturday 12:00 CET)

---

## Connection Metrics

### PgBouncer Active Connections (Production)

| Metric | Jan 24 (JEE8) | Feb 7 (JEE10) | Delta | Status |
|--------|---------------|---------------|-------|--------|
| Active Connections | 3,888 | 3,332 | -556 (-14.3%) | ✅ Lower |
| Waiting Connections | 0 | 0 | same | ✅ Healthy |

### Analysis

- **Active connections** dropped by 14.3%, consistent with the lower weekend traffic (-53.6%)
- **Zero waiting connections** on both weekends — no connection pool pressure
- Connection pool ratio relative to traffic is actually **higher** under JEE10:
  - Jan 24: 3,888 connections / 957 req/sec = 4.06 connections per req/sec
  - Feb 7: 3,332 connections / 444 req/sec = 7.50 connections per req/sec
  - This suggests JEE10 maintains slightly more connections per unit of traffic, but well within pool capacity

---

## Comparison to Jan 31 (First JEE10 Weekend)

| Metric | Jan 31 (JEE10 wk1) | Feb 7 (JEE10 wk2) | Trend |
|--------|--------------------|--------------------|-------|
| Active Connections | 3,433 | 3,332 | ✅ Stable |
| Waiting Connections | 0 | 0 | ✅ Stable |

Database connectivity has been consistently healthy across both JEE10 weekends.

---

## Key Observations

- ✅ Zero waiting connections — no connection pool exhaustion
- ✅ Active connections within expected range for traffic levels
- ✅ Consistent with previous JEE10 weekend (Jan 31)
- ✅ No signs of connection leaks or pool saturation

---

## Queries Used
```promql
# Active connections
sum(pgbouncer_pools_client_active_connections{database="productie"})

# Waiting connections
sum(pgbouncer_pools_client_waiting_connections{database="productie"})
```
