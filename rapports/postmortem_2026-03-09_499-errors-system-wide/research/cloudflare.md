# ☁️ Cloudflare Research: System-wide 499 Errors / Connection Pool Saturation

**Investigation Time Window:** 08:00 - 14:00 CET (07:00 - 13:00 UTC)
**Dashboard:** Cloudflared Tunnel (2WhbDNm7z)

## Tunnel Health

Cloudflared HA tunnel connections remained **stable at 8 connections per node** throughout the entire incident on all 3 Traefik pods:

| Node | Connections | Status |
|------|:-:|:-:|
| som-k8s-node01 (traefik-55564bb7c9-t695h) | 8 (constant) | ✅ Normal |
| som-k8s-node02 (traefik-55564bb7c9-nxbh6) | 8 (constant) | ✅ Normal |
| som-k8s-node04 (traefik-55564bb7c9-6q7j7) | 8 (constant) | ✅ Normal |

No tunnel drops, reconnections, or degradation detected during the entire investigation window.

## Cloudflare Tunnel Total Requests (All tunnels combined)

| Time (CET) | Time (UTC) | Requests/sec | Status |
|------------|------------|:---:|--------|
| 04:47 | 03:47 | 111 | ✅ Normal (overnight) |
| 06:00 | 05:00 | ~190 | ✅ Normal |
| 07:00 | 06:00 | ~400 | ✅ Morning ramp |
| 08:00 | 07:00 | ~950 | ✅ Normal peak traffic |
| 08:30 | 07:30 | ~1,360 | ✅ Normal |
| 09:00 | 08:00 | ~2,560 | ✅ Normal |
| 09:30 | 08:30 | ~3,100 | ✅ Normal peak |
| 10:00 | 09:00 | ~3,775 | ⚠️ High |
| 10:30 | 09:30 | ~4,550 | ⚠️ High |
| 11:00 | 10:00 | ~4,690 | ⚠️ Peak zone |
| 11:30 | 10:30 | ~4,860 | ⚠️ Peak zone |
| 12:08 | 11:08 | **5,640** | ⚠️ **Day peak** |
| 12:30 | 11:30 | ~4,574 | ⚠️ |
| 12:45 | 11:45 | ~2,856 | ⚠️ Declining |
| 13:00 | 12:00 | ~1,228 | ✅ Recovering |
| 13:15 | 12:15 | ~913 | ✅ Normal |

**Note:** The Cloudflare tunnel handles all incoming traffic. Traffic flows:
`Internet → Cloudflare Edge → Cloudflared Tunnel → Traefik → Services`

## Queries Used

```promql
# HA tunnel connections
cloudflared_tunnel_ha_connections{kubernetes_cluster="somtoday"}

# Total tunnel requests
sum(rate(cloudflared_tunnel_total_requests{kubernetes_cluster="somtoday"}[5m]))
```

## Key Observations

- ✅ **Cloudflare tunnel was NOT the cause of the incident.** All tunnel connections remained stable throughout.
- ✅ No tunnel reconnections, drops, or edge errors detected.
- The traffic pattern is a normal Monday morning ramp-up peaking around 12:08 CET (~5,640 req/s).
- Traffic naturally subsided after 12:30 CET, which contributed to the recovery.
- The 499 errors are NOT caused by Cloudflare timing out — they originate from the Traefik→backend layer where backends are too slow to respond.
