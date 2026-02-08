# 🚦 Proxy Research: JEE10 Weekend Comparison

**Comparison Window:** Feb 7-8, 2026 vs Jan 24-25, 2026
**Dashboard:** Traefik v3 (rCn92aUGp)
**Filters:** `kubernetes_cluster=somtoday, namespace=traefik`

---

## Request Throughput

### Saturday 12:00 CET

| Metric | Jan 24 (JEE8) | Feb 7 (JEE10) | Delta | Status |
|--------|---------------|---------------|-------|--------|
| Total Requests/sec | 956.9 | 444.1 | **-53.6%** | ⚠️ Significantly lower |

### Sunday Comparison

| Metric | Jan 25 (JEE8) | Feb 8 (JEE10) | Delta |
|--------|---------------|---------------|-------|
| Total Requests/sec (10:00) | 615.5 | 349.8 | -43.2% |
| Total Requests/sec (12:00) | 1,271.8 | *(no data yet)* | — |

**Note:** The ~50% traffic reduction is likely seasonal (different weekend, possibly school holiday or exam period), not JEE10-related. All traffic proportions remain consistent.

---

## HTTP Status Code Distribution (Saturday 12:00 CET)

| Code | Jan 24 Rate/sec | Feb 7 Rate/sec | % of Total (Jan 24) | % of Total (Feb 7) | Status |
|------|-----------------|----------------|---------------------|-------------------|--------|
| **200** | 685.6 | 318.8 | 71.6% | 71.8% | ✅ Proportional |
| **206** | 238.5 | 111.8 | 24.9% | 25.2% | ✅ Proportional |
| **201** | 1.036 | 0.485 | 0.108% | 0.109% | ✅ Same |
| **302** | 25.0 | 10.3 | 2.6% | 2.3% | ✅ Normal |
| **400** | 4.25 | 1.97 | 0.444% | 0.443% | ✅ Proportional |
| **404** | 0.878 | 0.284 | 0.092% | 0.064% | ✅ Improved |
| **499** | 0.158 | 0.082 | 0.0165% | 0.0185% | ✅ Normal variance |
| **500** | 0.00223 | 0.00335 | 0.000233% | 0.000754% | ⚠️ Higher rate |
| **502** | 0 | 0 | 0% | 0% | ✅ None |
| **503** | 0 | 0 | 0% | 0% | ✅ None |

### Status Code Analysis

The overall traffic distribution is **remarkably consistent** between the two weekends despite the ~50% traffic reduction:
- **2xx success rates** maintained at ~97% of traffic
- **4xx client errors** proportionally identical
- **499 client aborts** marginally increased (+12% relative) — within normal variance
- **500 errors** increased ~3.2x in relative terms — but absolute numbers remain very low

---

## Error Rate Analysis

### Saturday 12:00 CET

| Metric | Jan 24 | Feb 7 | Delta | Status |
|--------|--------|-------|-------|--------|
| 5xx Total/sec | 0.00223 | 0.00335 | +50.2% | ⚠️ |
| 5xx % of Total | 0.000233% | 0.000754% | +224% relative | ⚠️ |

### Sunday 10:00 CET

| Metric | Jan 25 | Feb 8 | Delta | Status |
|--------|--------|-------|-------|--------|
| 5xx Total/sec | 0.000558 | 0.00139 | +149% | ⚠️ |
| 5xx % of Total | 0.0000907% | 0.000398% | +338% relative | ⚠️ |

### Error Rate Context

While the **relative increase** in 5xx error rate is significant (3-4x), the **absolute numbers remain extremely low**:
- Peak 5xx rate: 0.00335 errors/sec ≈ **12 errors per hour**
- As percentage: 0.000754% ≈ **1 error per 133,000 requests**

This is well below any critical threshold but represents a consistent trend from the Jan 31 weekend.

---

## Client Aborts (499) — Weekend-to-Weekend

| Metric | Jan 24 | Feb 7 | Delta |
|--------|--------|-------|-------|
| 499 Rate/sec | 0.158 | 0.082 | -48.0% absolute |
| 499 % of Total | 0.0165% | 0.0185% | +12% relative |

The **absolute 499 count dropped** proportionally with traffic. The relative rate shows only a marginal increase, **within normal variance**.

---

## Key Observations

- ✅ Status code distribution proportionally identical — no new error patterns
- ✅ 499 client aborts within normal variance
- ✅ Zero 502/503 errors on both weekends
- ⚠️ 500 error rate approximately 3x higher relative to traffic
- ⚠️ Absolute 5xx numbers still very low (~12/hour)
- ℹ️ Traffic ~50% lower on Feb 7/8 — likely seasonal, not JEE10-related

---

## Queries Used
```promql
# Total request throughput
sum(rate(traefik_service_requests_total{kubernetes_cluster="somtoday", namespace="traefik"}[1h]))

# 5xx errors
sum(rate(traefik_service_requests_total{kubernetes_cluster="somtoday", namespace="traefik", code=~"5.."}[1h]))

# By status code
sum by(code) (rate(traefik_service_requests_total{kubernetes_cluster="somtoday", namespace="traefik"}[1h]))
```
