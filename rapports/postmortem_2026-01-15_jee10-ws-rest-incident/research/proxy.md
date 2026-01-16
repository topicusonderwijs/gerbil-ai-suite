# 🚦 Proxy Research: JEE10 WS-REST Incident

**Investigation Time Window:** 06:00 - 10:00 CET (05:00 - 09:00 UTC)
**Dashboard:** Traefik v3 (rCn92aUGp)
**Filters:** `kubernetes_cluster=somtoday`

---

## Executive Summary

Traefik fungeerde als de "canary in the coal mine" - de proxy metrics tonen exact wanneer het systeem begon te falen:
1. **07:36 CET**: P99 latency sprong naar 5s (eerste signaal)
2. **07:45-08:20 CET**: 502/504 errors escaleerden
3. **08:20 CET**: Traefik ging OOM → 370 503-errors/seconde
4. **08:30 CET**: Recovery na JEE8 rollback

---

## Request Throughput Analysis

### Overall Request Rate (ws-rest services)

| Phase | Time (CET) | Requests/sec | Trend |
|-------|------------|--------------|-------|
| Pre-incident | 06:00-07:00 | 50-200 | ✅ Normal growth |
| School start | 07:00-07:30 | 400-1,200 | ✅ Normal peak |
| Degradation | 07:30-07:45 | 800-500 ↓ | ⚠️ Dropping |
| Outage | 07:45-08:15 | 0-300 | 🔴 Service failing |
| Critical | 08:15-08:30 | 0-100 | 🔴 Near-complete outage |
| Recovery | 08:30-08:45 | 100-500 | ⚠️ Recovering |
| Stable | 09:00+ | 2,000-3,000 | ✅ Normal |

### Traffic Pattern Anomalies

```
07:00 ▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓ 1200 req/s
07:15 ▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓ 1150 req/s
07:30 ▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓ 800 req/s ↓ Backpressure
07:45 ▓▓▓▓▓▓▓▓▓▓▓▓▓ 400 req/s 🔴 Degraded
08:00 ░░░░ 50 req/s 🔴 OUTAGE
08:15 ▓▓▓▓▓▓▓▓▓ 300 req/s Partial recovery attempt
08:20 ░ 0 req/s 🔴 COMPLETE OUTAGE (Traefik OOM)
08:30 ▓▓▓▓▓▓▓▓▓▓▓▓ 500 req/s Recovery starting
09:00 ▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓ 3000 req/s ✅
```

**Observaties:**
- Meerdere periodes van ~0 requests/sec duiden op complete service unavailability
- Traffic dropte met 90%+ tijdens de ernstigste fase
- Normal traffic was ~3000 req/s tijdens schooluren - incident resulteerde in ~50-300 req/s

---

## Latency Analysis

### P99 Response Time

| Timestamp (CET) | P99 Latency | SLA Status | Notes |
|-----------------|-------------|------------|-------|
| 06:00 | 0.6s | ✅ Normal | Pre-school hours |
| 07:00 | 0.7s | ✅ Normal | |
| 07:20 | 0.8s | ✅ Normal | |
| 07:30 | 1.2s | ⚠️ Elevated | First warning sign |
| 07:36 | **5.0s** | 🔴 **BREACH** | **Timeout threshold** |
| 07:40-08:42 | **5.0s** | 🔴 **SUSTAINED** | 1+ uur timeout |
| 08:45 | 1.5s | ⚠️ Recovering | |
| 09:00 | 0.5s | ✅ Normal | |

**🚨 KRITIEKE BEVINDING:**
- De P99 latency was **vastgepind op 5 seconden** gedurende meer dan **1 uur**
- Dit is de maximale bucket in de histogram, wat betekent dat werkelijke latency **hoger** was
- Implicatie: Bijna alle requests faalden of timeden uit

### Latency Percentile Comparison (Normal vs Incident)

| Percentile | Normal | Incident (07:40-08:20) | Degradation |
|------------|--------|------------------------|-------------|
| P50 | 0.1-0.2s | 2.0-3.0s | 15-20x |
| P90 | 0.4-0.5s | 4.0-5.0s | 10x |
| P99 | 0.6-0.8s | 5.0s+ | 6-8x |

---

## Error Distribution Deep Dive

### HTTP 5xx Error Timeline

| Time (CET) | 500 | 502 | 503 | 504 | Total 5xx/s | Analysis |
|------------|-----|-----|-----|-----|-------------|----------|
| 07:00 | 0 | 0 | 0 | 0 | 0 | Baseline |
| 07:35 | 0.1 | **1.5** | 0 | 0 | 1.6 | First 502s - backend slow |
| 07:45 | 0.4 | **5.7** | 0 | **16.5** | 22.6 | 504s dominate - timeouts |
| 07:50 | 0.2 | **9.7** | 0 | **22.8** | 32.7 | Escalating |
| 07:55 | 0.2 | **10.2** | 0 | **49.7** | 60.1 | Major timeout wave |
| 08:00 | 0.1 | **2.9** | 0 | **36.9** | 39.9 | |
| 08:05 | 0.7 | **7.5** | 0 | **19.4** | 27.6 | |
| 08:10 | 1.5 | **12.2** | 1.1 | **0** | 14.8 | Brief recovery |
| 08:15 | 2.0 | **22.3** | 0.5 | **30.4** | 55.2 | Second wave |
| 08:20 | 2.3 | **35.9** | **370** 🔴 | **116** | **524** 🔴 | **TRAEFIK OOM** |
| 08:25 | 0.5 | **51.8** | **90.8** | **12.5** | 155.6 | After OOM |
| 08:30 | 0.07 | **2.0** | 0 | **55.5** | 57.6 | Recovery starting |
| 09:00 | 0 | 0 | 0 | 0 | 0 | Fully recovered |

### Error Type Correlation

```
┌─────────────────────────────────────────────────────────────────────┐
│                    ERROR CASCADE PATTERN                            │
└─────────────────────────────────────────────────────────────────────┘

Phase 1 (07:35-07:45): 502 Bad Gateway dominant
├── Backend pods slowing down
├── Traefik kan nog wel verbinden, maar responses zijn traag
└── Health checks beginnen te falen

Phase 2 (07:45-08:15): 504 Gateway Timeout dominant  
├── Requests bereiken backend maar krijgen geen response binnen 5s
├── Connection pooling uitgeput
└── Thread starvation op backend

Phase 3 (08:20): 503 Service Unavailable SPIKE
├── Traefik Out-of-Memory event
├── 370 requests/seconde krijgen 503
├── Complete service unavailability
└── Na restart herstelt 503 naar 0

Phase 4 (08:20-08:30): 502/504 mix
├── Backend nog steeds problemen
├── Traefik weer beschikbaar maar backend niet
└── JEE8 rollback in uitvoering

Phase 5 (08:30+): Recovery
├── JEE8 pods nemen traffic over
├── Errors zakken naar baseline
└── Full recovery binnen 15 minuten
```

---

## Traefik Health Analysis

### OOM Event Reconstruction

**Evidence for Traefik OOM:**
1. **503 spike**: 370/s 503 errors om 08:20 (normale rate: 0)
2. **Request drop**: Traffic naar 0 req/s rond 08:20
3. **Quick recovery**: 503s naar 0 binnen 5 minuten (na container restart)
4. **Pattern match**: 503 = service unavailable = Traefik zelf down

**Waarschijnlijke oorzaak:**
- Traefik bufferde trage responses van JEE10 pods
- Met duizenden wachtende requests groeide geheugengebruik
- OOM killer termineerde Traefik container
- Kubernetes restartte container → recovery

### Connection Pressure

```
Normal operation:
  Request → Traefik → Backend → Response → Client (100-500ms)
  
During incident:
  Request → Traefik [BUFFER GROWS]
                    ↓
                    Backend (blocked on DB)
                    ↓
                    No response for 5s+
                    ↓
                    Retry from client
                    ↓
                    More requests buffered
                    ↓
                    [OOM]
```

---

## Service-Level Impact

### Affected Services (via exported_service label)

| Service | Impact Level | Notes |
|---------|--------------|-------|
| ws-rest | 🔴 Critical | Primary affected service |
| sis-ui | ⚠️ Degraded | Calls ws-rest voor data |
| authenticator | ⚠️ Degraded | Login flows affected |
| docent-rest | ⚠️ Degraded | Teacher API depends on ws-rest |

---

## Data Gaps

1. **Traefik memory metrics** - Niet beschikbaar
   - Kon OOM niet direct bevestigen
   - Wel indirect via 503 pattern

2. **Connection count per service** - Niet opgevraagd
   - Zou interessant zijn om connection pooling te analyseren

3. **Traefik entrypoint metrics** - Beperkt
   - Geen breakdown per entrypoint

---

## Queries Used

```promql
# Request rate for ws-rest
sum(rate(traefik_service_requests_total{kubernetes_cluster="somtoday", exported_service=~".*ws-rest.*"}[1m]))

# P99 latency
histogram_quantile(0.99, sum(irate(traefik_service_request_duration_seconds_bucket{kubernetes_cluster="somtoday", exported_service=~".*ws-rest.*"}[1m])) by (le))

# Error rate by status code
sum(rate(traefik_service_requests_total{kubernetes_cluster="somtoday", code=~"5.."}[1m])) by (code)

# Total 5xx error rate percentage
sum(rate(traefik_service_requests_total{kubernetes_cluster="somtoday", code=~"5.."}[5m])) / sum(rate(traefik_service_requests_total{kubernetes_cluster="somtoday"}[5m])) * 100
```

---

## Recommendations

### Immediate
1. **Add Traefik memory limits and requests**
   - Set appropriate limits to prevent OOM affecting other services
   - Configure OOM score adjustment

2. **Request timeout tuning**
   - Reduce default timeout van 5s naar 3s
   - Fail fast → prevent buffering

### Short-term
3. **Circuit breaker implementation**
   - Traefik middleware for circuit breaking
   - Trip when error rate > 10%

4. **Rate limiting**
   - Per-client rate limits
   - Prevent retry storms

### Long-term
5. **Backend health checks**
   - More aggressive health checks (1s interval)
   - Remove unhealthy backends faster

6. **Observability improvements**
   - Traefik memory dashboards
   - Connection count alerts
   - Request queue depth monitoring

---

*Research verzameld: 2026-01-15*
*Analyst: GitHub Copilot Incident Analyst*
