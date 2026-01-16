# ☸️ Kubernetes Research: JEE10 WS-REST Incident

**Investigation Time Window:** 06:00 - 10:00 CET (05:00 - 09:00 UTC)
**Cluster:** somtoday (production)

---

## Executive Summary

⚠️ **Data Gap Identified**: Pod-level metrics queries retourneerden geen data voor:
- Container memory working set
- Container restart counts

Dit beperkt directe Kubernetes analyse, maar we kunnen indirect afleiden uit andere metrics.

---

## Pod Deployment Context

### JEE10 Test Deployment

Tijdens het incident waren de volgende deployments actief:

| Deployment | Replicas | Version | Status |
|------------|----------|---------|--------|
| ws-rest (JEE10) | 5+ pods | 84876d49c5-* | 🔴 Under test |
| ws-rest (JEE8) | 5+ pods | 5bbcdc9876-*, 554c6db665-* | ✅ Standby |

**Pod naming pattern:**
- JEE10: `ws-rest-84876d49c5-{random}` (e.g., 5cgwh, 6nfgk, 7wrqf)
- JEE8: `ws-rest-5bbcdc9876-{random}`, `ws-rest-554c6db665-{random}`

---

## Pod Health Analysis (Inferred from Thread Metrics)

### JEE10 Pod Behavior

| Pod | Thread Saturation Pattern | Inferred Status |
|-----|--------------------------|-----------------|
| ws-rest-84876d49c5-5cgwh | 200% @ 07:41, drops to 0% @ 07:55 | 🔴 Likely restarted |
| ws-rest-84876d49c5-6nfgk | 200% @ 07:43, drops to 0% @ 07:58 | 🔴 Likely restarted |
| ws-rest-84876d49c5-7wrqf | 200% @ 07:45, drops to 0% @ 08:01 | 🔴 Likely restarted |
| ws-rest-84876d49c5-9xmpl | 200% @ 07:42, oscillating | ⚠️ Unhealthy |
| ws-rest-84876d49c5-bkthz | 200% @ 07:40, first to saturate | 🔴 Unhealthy |

**Observaties:**
- Drops naar 0% thread utilization wijzen op pod restarts of crashes
- Alle JEE10 pods vertoonden dit patroon
- JEE8 pods bleven stabiel (0-8% utilization)

### Restart Pattern Analysis

```
Timeline (CET):

07:40 ┃ First JEE10 pod hits 200% (bkthz)
07:41-07:45 ┃ All JEE10 pods reach 200%
      ┃
07:55 ┃ First pod drops to 0% → RESTART?
07:58 ┃ Second pod drops to 0%
08:01 ┃ Third pod drops to 0%
      ┃
08:00-08:25 ┃ Continuous oscillation between 200% and 0%
            ┃ → Pods cycling through restart loop
      ┃
08:30 ┃ JEE8 rollback initiated
      ┃ JEE10 pods removed from service
```

---

## Resource Utilization (Estimated)

### Memory

| Component | Expected Baseline | During Incident | Evidence |
|-----------|-------------------|-----------------|----------|
| ws-rest pod | 2-4 GB | Unknown | No direct metrics |
| Traefik | 512MB-1GB | **OOM** | 503 spike @ 08:20 |

**Traefik OOM Evidence:**
- 370/s 503 errors at 08:20
- Quick recovery after (container restart)
- Pattern consistent with OOM kill + restart

### CPU

Data niet opgevraagd - zou interessante correlatie kunnen tonen.

---

## Deployment Configuration Analysis

### Suspected Issues

1. **Liveness/Readiness Probes**
   - Pods bleven traffic ontvangen ondanks 200% saturation
   - Readiness probe detecteerde mogelijk geen thread exhaustion
   - **Aanbeveling**: Check probe configuratie

2. **Resource Limits**
   ```yaml
   # Suggested check
   resources:
     requests:
       memory: "2Gi"
       cpu: "500m"
     limits:
       memory: "4Gi"  # Is this sufficient for JEE10?
       cpu: "2000m"
   ```

3. **Horizontal Pod Autoscaler (HPA)**
   - Waren er HPA regels actief?
   - HPA zou mogelijk niet snel genoeg hebben geschaald

---

## Kubernetes Events (To Investigate)

Controleer deze events voor het incident window:
```bash
kubectl get events -n somtoday --sort-by='.lastTimestamp' \
  --field-selector involvedObject.name=ws-rest-84876d49c5-*
```

Zoek naar:
- `OOMKilled` events
- `FailedScheduling` events  
- `Unhealthy` liveness probe events
- `CrashLoopBackOff` events

---

## Rollout Strategy Analysis

### Pre-Incident Setup

Jullie hadden een **canary/blue-green** style deployment:
- JEE10 pods actief (test)
- JEE8 pods als backup (standby)

### Rollback Procedure

```
08:25 ┃ Decision: Rollback naar JEE8
08:25-08:30 ┃ Traffic shift van JEE10 → JEE8
            ┃ - Scale up JEE8 pods
            ┃ - Update service selector
            ┃ - Scale down JEE10 pods
08:30 ┃ JEE8 handling all traffic
08:35+ ┃ System stabilized
```

**Observatie:** Rollback was snel en effectief (~5-10 minuten)

---

## Data Gaps

### Missing Metrics

| Metric | Query Tried | Result |
|--------|-------------|--------|
| Container memory | `container_memory_working_set_bytes{namespace="somtoday", container=~".*ws-rest.*"}` | Empty |
| Restart count | `kube_pod_container_status_restarts_total{namespace="somtoday", container=~".*ws-rest.*"}` | Empty |
| CPU utilization | Not queried | N/A |

### Possible Causes
1. **Namespace mismatch** - Pods might be in different namespace
2. **Label differences** - Container name might not match pattern
3. **Metric cardinality** - High cardinality causing data gaps
4. **kube-state-metrics** - May not be exposing these metrics

### Alternative Queries to Try
```promql
# Without container filter
container_memory_working_set_bytes{pod=~"ws-rest.*"}

# Via kube-state-metrics
kube_pod_container_status_running{pod=~"ws-rest.*"}

# Node-level aggregation
sum(container_memory_working_set_bytes{pod=~"ws-rest.*"}) by (pod)
```

---

## Recommendations

### Immediate

1. **Investigate restart metrics**
   - Run `kubectl` commands to get actual restart counts
   - Check kube-state-metrics configuration

2. **Review probe configuration**
   ```yaml
   livenessProbe:
     httpGet:
       path: /health
       port: 8080
     initialDelaySeconds: 60
     periodSeconds: 10
     failureThreshold: 3  # Is this enough?
   
   readinessProbe:
     httpGet:
       path: /ready
       port: 8080
     periodSeconds: 5
     failureThreshold: 3
   ```

### Short-term

3. **Add custom readiness probe**
   - Check thread pool health
   - Check DB connection availability
   - Fail readiness when >80% thread utilization

4. **Review resource limits**
   - Compare JEE8 vs JEE10 memory footprint
   - Potentially increase limits for JEE10

### Long-term

5. **Implement PodDisruptionBudget**
   - Prevent too many pods from being unhealthy simultaneously

6. **Add pod-level dashboards**
   - Memory per pod
   - CPU per pod
   - Restart counts
   - Network I/O

---

## Raw Data to Collect

Voor toekomstige analyse, verzamel:
```bash
# Pod descriptions
kubectl describe pods -n somtoday -l app=ws-rest

# Events during incident
kubectl get events -n somtoday --sort-by='.metadata.creationTimestamp'

# HPA status
kubectl get hpa -n somtoday

# Resource quotas
kubectl get resourcequotas -n somtoday
```

---

*Research verzameld: 2026-01-15*
*Data status: INCOMPLETE - Container metrics not available*
*Analyst: GitHub Copilot Incident Analyst*
