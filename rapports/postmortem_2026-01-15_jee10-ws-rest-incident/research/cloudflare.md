# ☁️ Cloudflare Research: JEE10 WS-REST Incident

**Investigation Time Window:** 06:00 - 10:00 CET (05:00 - 09:00 UTC)
**Dashboard:** Cloudflared Tunnel (2WhbDNm7z)

---

## Executive Summary

⚠️ **Data Gap Identified**: De query voor Cloudflare tunnel metrics retourneerde **geen data** voor de `cloudflared_tunnel_active_connections` metric met `kubernetes_cluster="somtoday"`.

Dit kan betekenen:
1. De metric label is anders geconfigureerd
2. De tunnel draait in een andere namespace/cluster
3. Metric scraping was niet actief tijdens incident

---

## Available Data

De originele postmortem vermeldde:
> "Cloudflare Tunnel niet meer bereikbaar → landschap volledig plat"

Dit is indirect bevestigd door:
1. **Traefik 503 errors** - Traefik ging OOM, wat Cloudflare tunnel backend zou verliezen
2. **Complete traffic drop** - 0 requests/sec periodes in Traefik metrics
3. **502 Bad Gateway errors** - Backend services onbereikbaar

---

## Indirect Evidence from Other Metrics

### Tunnel Health Indicators (Inferred)

| Timestamp (CET) | Status | Evidence |
|-----------------|--------|----------|
| 06:00-07:30 | ✅ Operational | Normal traffic flow |
| 07:30-07:45 | ⚠️ Degraded | Elevated latency (5s) |
| 07:45-08:00 | 🔴 Partially Down | Intermittent 502s |
| 08:00-08:20 | 🔴 Critical | Major traffic drops |
| 08:20 | 🔴 **Down** | 503 spike = Traefik OOM = no backend for tunnel |
| 08:20-08:30 | 🔴 Recovery | Traefik restart |
| 08:30+ | ✅ Operational | JEE8 rollback complete |

---

## Cloudflare Tunnel Architecture

```
                    ┌──────────────────┐
                    │   Cloudflare     │
                    │   Edge Network   │
                    └────────┬─────────┘
                             │
                    ┌────────▼─────────┐
                    │   cloudflared    │
                    │   (Tunnel Pod)   │
                    └────────┬─────────┘
                             │
                    ┌────────▼─────────┐
                    │     Traefik      │ ← OOM @ 08:20
                    │    (Ingress)     │
                    └────────┬─────────┘
                             │
          ┌──────────────────┼──────────────────┐
          │                  │                  │
    ┌─────▼─────┐     ┌─────▼─────┐     ┌─────▼─────┐
    │  ws-rest  │     │  sis-ui   │     │   auth    │
    │  (JEE10)  │ ← Exhausted threads  │           │
    └───────────┘     └───────────┘     └───────────┘
```

**Cascade Path:**
1. ws-rest (JEE10) threads exhausted wachtend op DB
2. Traefik bufferde wachtende requests
3. Traefik ging OOM
4. Cloudflare tunnel verloor backend (Traefik)
5. End users zagen complete outage

---

## Data Gap Documentation

### Missing Metrics
- `cloudflared_tunnel_active_connections{kubernetes_cluster="somtoday"}`
- `cloudflared_tunnel_requests_total`
- `cloudflared_tunnel_request_errors_total`

### Potential Causes
1. **Different cluster label** - Tunnel mogelijk in management cluster
2. **Namespace filtering** - Tunnel niet in "somtoday" namespace
3. **Metric exporter issues** - Cloudflared exporter niet actief

### Recommended Query Variations
```promql
# Try without cluster filter
cloudflared_tunnel_active_connections

# Try with different label
cloudflared_tunnel_active_connections{namespace="cloudflare"}

# Try tunnel name
cloudflared_tunnel_active_connections{tunnel="somtoday-prod"}
```

---

## Recommendations

### Monitoring Improvements
1. **Verify cloudflared metrics exposure**
   - Check if prometheus is scraping cloudflared pods
   - Verify label configuration

2. **Add tunnel-specific alerts**
   - Alert when tunnel connections drop
   - Alert when tunnel error rate increases

3. **Dashboard updates**
   - Add cloudflared metrics to existing dashboards
   - Create dedicated tunnel health dashboard

### Documentation
4. **Update incident runbook**
   - Include Cloudflare tunnel status checks
   - Document tunnel restart procedures

---

## Alternative Investigation Paths

Als Cloudflare metrics niet beschikbaar zijn via Grafana:
1. **Cloudflare Dashboard** - Check tunnel health in CF portal
2. **cloudflared logs** - Check pod logs voor errors
3. **Kubernetes events** - Check voor pod restarts/OOMKills

---

*Research verzameld: 2026-01-15*
*Data status: INCOMPLETE - Metric not available*
*Analyst: GitHub Copilot Incident Analyst*
