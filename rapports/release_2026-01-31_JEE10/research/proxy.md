# 🚦 Proxy Research: JEE10 Migration Release

**Release Time Window:** 2026-01-31 to 2026-02-01 CET
**Dashboard:** Traefik v3 (rCn92aUGp)
**Filters:** `kubernetes_cluster=somtoday`

## Request Throughput

### Overall Traffic

| Metric | JEE8 (Jan 30 12:00) | JEE10 (Feb 2 12:00) | Delta | Status |
|--------|---------------------|---------------------|-------|--------|
| Total Requests/sec | 3,940.84 | 4,422.08 | +481.24 (+12.2%) | ✅ Normal |

### HTTP Status Code Distribution

| Status Code | JEE8 Rate/sec | JEE10 Rate/sec | Delta | Status |
|-------------|---------------|----------------|-------|--------|
| **200** | 2,866.52 | 3,246.04 | +379.52 (+13.2%) | ✅ Normal |
| **206** | 913.55 | 994.32 | +80.77 (+8.8%) | ✅ Normal |
| **302** | 139.20 | 158.01 | +18.81 (+13.5%) | ✅ Normal |
| **304** | 0.51 | 0.39 | -0.12 (-23.5%) | ✅ Normal |
| **400** | 8.04 | 8.99 | +0.95 (+11.8%) | ✅ Normal |
| **401** | 2.69 | 3.15 | +0.46 (+17.1%) | ✅ Normal |
| **403** | 1.66 | 1.95 | +0.29 (+17.5%) | ✅ Normal |
| **404** | 0.68 | 0.82 | +0.14 (+20.6%) | ✅ Normal |
| **499** | 1.72 | 2.28 | +0.56 (+32.6%)* | ✅ Normal* |
| **500** | 0.078 | 0.098 | +0.020 (+25.6%) | ⚠️ Elevated |
| **502** | 0.0017 | 0.0047 | +0.003 (+176%) | ⚠️ Spike |
| **503** | 0.00056 | 0 | -0.00056 | ✅ Improved |

### Error Rate Analysis

| Error Category | JEE8 | JEE10 | Delta | Status |
|----------------|------|-------|-------|--------|
| 5xx Total/sec | 0.080 | 0.103 | +0.023 (+29%) | ⚠️ Elevated |
| 5xx % of Total | 0.0020% | 0.0023% | +0.0003% | ⚠️ Slight |
| 4xx Total/sec | 13.07 | 14.87 | +1.80 (+13.8%) | ✅ Normal |

### 5xx Error Breakdown
- **500 Internal Server Error**: +25.6% increase
- **502 Bad Gateway**: +176% increase (but very low absolute numbers: ~0.005/sec)
- **503 Service Unavailable**: Improved to 0

### Client Aborts (499)

*⚠️ The 32.6% figure above compares weekday-to-weekday raw rates. A proper weekend-to-weekend comparison shows a smaller increase:*

| Weekend | Day | Total Requests (1h) | 499 Count | 499 Rate |
|---------|-----|---------------------|-----------|----------|
| **JEE8** | Sat Jan 24 | 3.6M | 665 | 0.0185% |
| **JEE8** | Sun Jan 25 | 5.0M | 810 | 0.0163% |
| **JEE10** | Sat Jan 31 | 2.7M | 554 | 0.0204% |
| **JEE10** | Sun Feb 1 | 3.8M | 669 | 0.0177% |

**Normalized weekend-to-weekend 499 rate increase: ~10%** (not 32.6%)

The modest increase is within acceptable variance and may be related to JEE10 warmup effects.

## Key Observations

- ✅ Overall throughput healthy (+12.2% normal variation)
- ✅ Success rates (2xx) proportionally maintained
- ⚠️ 5xx errors increased by 29% (but still only 0.0023% of total traffic)
- ⚠️ 502 Bad Gateway errors spiked 176% (very low absolute numbers)
- ✅ Client aborts (499) increased ~10% (weekend-to-weekend normalized) — within normal variance
- ✅ 503 errors eliminated completely
- ✅ 3xx redirects functioning normally

## Regression Indicators

1. **Internal server errors**: 500 errors up 25.6%
2. **Gateway errors**: 502 errors increased significantly (percentage-wise)

~~Potential latency regression~~: Client aborts (499) showed only ~10% increase when comparing weekend-to-weekend, which is within normal variance.

These require investigation to determine if they're JEE10-related regressions.

## Queries Used
```promql
# Total request throughput
sum(rate(traefik_service_requests_total{kubernetes_cluster="somtoday"}[1h]))

# 5xx errors
sum(rate(traefik_service_requests_total{kubernetes_cluster="somtoday", code=~"5.."}[1h]))

# By status code
sum by(code) (rate(traefik_service_requests_total{kubernetes_cluster="somtoday"}[1h]))
```
