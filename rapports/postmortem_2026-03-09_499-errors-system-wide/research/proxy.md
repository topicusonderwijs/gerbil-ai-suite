# 🚦 Proxy Research: System-wide 499 Errors / Connection Pool Saturation

**Investigation Time Window:** 08:00 - 14:00 CET (07:00 - 13:00 UTC)
**Dashboard:** Traefik v3 (rCn92aUGp)
**Filters:** `kubernetes_cluster=somtoday`

## Overall HTTP Status Code Distribution (All Services Combined)

| Time (CET) | 200 | 206 | 302 | 499 | 504 | 500 | 502 | Error Rate |
|------------|:---:|:---:|:---:|:---:|:---:|:---:|:---:|:---:|
| 08:00 | 2,809/s | 883/s | 70/s | 0.8/s | 0/s | 0/s | 0/s | ✅ ~0% |
| 09:00 | 3,466/s | 987/s | 194/s | 2.3/s | 0/s | 0/s | 0/s | ✅ ~0% |
| 09:50 | 3,339/s | 960/s | 195/s | 2.7/s | 0/s | 0/s | 0/s | ⚠️ 0.06% |
| **10:00** | 3,499/s | 992/s | 246/s | **137.8/s** | **8.8/s** | 0.4/s | **6.8/s** | 🔴 **3.2%** |
| 10:30 | 3,429/s | 987/s | 190/s | 3.5/s | 0/s | 0.2/s | 0/s | ⚠️ 0.08% |
| **11:00** | **1,755/s** | **439/s** | 110/s | **153.5/s** | **14.2/s** | **14.8/s** | 1.8/s | 🔴 **7.7%** |
| **12:00** | 2,430/s | 687/s | 216/s | **145.5/s** | **21.6/s** | 6.9/s | 1.6/s | 🔴 **5.0%** |

### Peak Error Rates

| Code | Description | Peak Rate | Peak Time (CET) |
|------|-------------|:---:|:---:|
| 499 | Client Closed Request | **243.1/s** | 12:38 |
| 504 | Gateway Timeout | **142.7/s** | 12:33 |
| 500 | Internal Server Error | **35.3/s** | 12:38 |
| 502 | Bad Gateway | **7.7/s** | 12:43 |
| 503 | Service Unavailable | 0.3/s | 09:53 |

## 499 Errors by Service (Top Affected)

| Service | Peak 499 Rate | Peak Time (CET) | Sustained Samples |
|---------|:---:|:---:|:---:|
| **authenticator** | **224.71/s** | 10:38 | 94 |
| **ws-rest** | **143.30/s** | 10:08 | 97 |
| **sis-ui** | **24.19/s** | 10:08 | 81 |
| **docent-graphql** | **8.18/s** | 10:43 | 63 |
| **schoolcommunicatie-rest** | 1.15/s | 10:08 | 37 |
| **docent-angular** | 0.01/s | 10:58 | 25 |

## 5xx Errors by Service (Top Affected)

| Service | Code | Peak Rate | Peak Time (CET) |
|---------|:---:|:---:|:---:|
| **authenticator** | 504 | **66.27/s** | 12:28 |
| **ws-rest** | 504 | **59.34/s** | 11:38 |
| **sis-ui** | 504 | **37.52/s** | 12:38 |
| **authenticator** | 500 | **34.73/s** | 12:38 |
| **ws-rest** | 500 | 7.49/s | 11:08 |
| **ws-rest** | 502 | 5.61/s | 10:08 |
| **sis-ui** | 502 | 5.52/s | 12:38 |
| **docent-graphql** | 504 | 4.25/s | 10:03 |
| **authenticator** | 502 | 1.94/s | 11:03 |

## P99 Request Latency (Key Services)

| Time (CET) | ws-rest | authenticator | sis-ui | sis-ui-landelijk | docent-graphql | Status |
|------------|:---:|:---:|:---:|:---:|:---:|--------|
| 08:00 | 729ms | 338ms | 1.1s | 297ms | 1.8s | ✅ Normal |
| 09:00 | 929ms | 837ms | 2.9s | 298ms | 3.7s | ⚠️ sis-ui already high |
| 09:50 | 966ms | 866ms | 3.4s | 1.1s | 5.0s | ⚠️ docent-graphql at limit |
| **10:00** | **5.0s** | 1.9s | **5.0s** | **5.0s** | **5.0s** | 🔴 **TIMEOUT** |
| 10:30 | 992ms | 1.1s | 3.9s | 5.0s | 5.0s | 🔴 Partial recovery |
| **11:00** | 3.1s | **5.0s** | **5.0s** | **5.0s** | **5.0s** | 🔴 **All at timeout** |
| 12:00 | 970ms | **5.0s** | **5.0s** | 296ms | **5.0s** | 🔴 Mixed |

## Docent-GraphQL Detailed Request Rates

| Time (CET) | 200 OK | 499 | 504 | 502 | Total Success Rate |
|------------|:---:|:---:|:---:|:---:|:---:|
| 08:00 | 42.3/s | 0/s | 0/s | 0/s | ✅ ~100% |
| 09:00 | 143.0/s | 0.02/s | 0/s | 0/s | ✅ ~100% |
| 09:50 | 151.9/s | 0.06/s | 0/s | 0.01/s | ✅ ~100% |
| **10:00** | 179.2/s | **2.09/s** | **5.79/s** | 0.01/s | 🔴 **96%** |
| 10:30 | 150.4/s | 0.05/s | 0/s | 0.01/s | ⚠️ ~100% |
| **11:00** | **27.8/s** | **6.35/s** | 0.07/s | 0/s | 🔴 **81%** |
| **12:00** | **2.9/s** | 0.12/s | 0.41/s | 0/s | 🔴 **84%** (near-dead) |

## Queries Used

```promql
# Overall HTTP status codes
sum(rate(traefik_service_requests_total{kubernetes_cluster="somtoday"}[5m])) by (code)

# 499 errors by service
sum(rate(traefik_service_requests_total{kubernetes_cluster="somtoday", code=~"499"}[5m])) by (exported_service)

# 5xx errors by service and code
sum(rate(traefik_service_requests_total{kubernetes_cluster="somtoday", code=~"5.."}[5m])) by (exported_service, code)

# P99 latency for key services
histogram_quantile(0.99, sum(rate(traefik_service_request_duration_seconds_bucket{kubernetes_cluster="somtoday", exported_service=~".*(ws-rest|sis-ui|authenticator).*"}[5m])) by (le, exported_service))

# Docent services detailed
sum(rate(traefik_service_requests_total{kubernetes_cluster="somtoday", exported_service=~".*docent.*"}[5m])) by (exported_service, code)
histogram_quantile(0.99, sum(rate(traefik_service_request_duration_seconds_bucket{kubernetes_cluster="somtoday", exported_service=~".*docent.*"}[5m])) by (le, exported_service))
```

## Key Observations

- 🔴 **System-wide impact**: Every major service (ws-rest, authenticator, sis-ui, docent-graphql) hit the 5.0s timeout ceiling
- 🔴 **499 errors dominated**: Peak 243.1/s at 12:38 CET — clients giving up before servers respond
- 🔴 **504 Gateway Timeouts**: Peak 142.7/s at 12:33 CET — Traefik timing out waiting for backends
- 🔴 **docent-graphql throughput collapsed**: From 152 req/s to 2.9 req/s (98% drop) by 12:00 CET
- ⚠️ **sis-ui latency was already elevated at 09:00 CET** (2.9s P99) before the main incident — possible early warning sign
- The error pattern shows two distinct phases:
  - **Phase 1 (10:00 CET)**: Sharp spike in 499 and 502 errors, brief partial recovery at 10:30
  - **Phase 2 (11:00-12:38 CET)**: Sustained degradation with all error types elevated
- **authenticator** was the most-affected service by 499 errors (224.71/s peak), indicating authentication failures cascading to all user-facing services
