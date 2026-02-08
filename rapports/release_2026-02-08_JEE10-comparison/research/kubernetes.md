# ☸️ Kubernetes & Cloudflare Tunnel Research: JEE10 Weekend Comparison

**Comparison Window:** Feb 7, 2026 vs Jan 24, 2026 (Saturday 12:00 CET)
**Cluster:** somtoday (production)

---

## Cloudflare Tunnel Status

### HA Connections

| Pod | Node | Jan 24 | Feb 7 | Status |
|-----|------|--------|-------|--------|
| traefik-55564bb7c9-t695h | som-k8s-node01 | 8 | **missing** | 🔴 Down |
| traefik-55564bb7c9-nxbh6 | som-k8s-node02 | 8 | 8 | ✅ Stable |
| traefik-55564bb7c9-6q7j7 | som-k8s-node04 | 8 | 8 | ✅ Stable |
| **Total** | — | **24** | **16** | ⚠️ Reduced |

### 🔴 Critical Finding: Missing Tunnel Pod

The Cloudflare tunnel pod on **som-k8s-node01** is no longer reporting metrics as of Feb 7. This represents:
- **33% reduction** in HA tunnel capacity (24 → 16 connections)
- Same pod template hash (`55564bb7c9`) — no rollout occurred
- Pod was present on Jan 24, Jan 31 reports

**Possible causes:**
- Node01 maintenance or failure
- Pod eviction or crash loop
- Intentional scaling change

**Impact assessment:**
- Remaining 2 pods appear to handle the reduced weekend traffic adequately
- Could become critical under high weekday traffic loads
- Reduces redundancy if another pod fails

---

## Tunnel Request Throughput

| Metric | Jan 24 | Feb 7 | Delta | Status |
|--------|--------|-------|-------|--------|
| Tunnel Requests/sec | 955.3 | 443.5 | -53.6% | ✅ (proportional to traffic) |
| Tunnel Errors/sec | 0.167 | 0.086 | -48.6% | ✅ Lower |
| Error Rate | 0.0175% | 0.0194% | +10.9% | ⚠️ Slight increase |

### Tunnel Error Rate Context

The tunnel error rate increased slightly (+10.9% relative) despite lower absolute errors. This is within normal variance and not concerning at current traffic levels.

---

## Traefik Ingress

- Pod template hash unchanged: `55564bb7c9` — no Traefik rollout since before Jan 24
- Same deployment configuration across both comparison periods

---

## Key Observations

- 🔴 **node01 tunnel pod missing** — reduced from 3 to 2 HA pods
- ✅ Remaining tunnel infrastructure healthy
- ✅ Tunnel error rate acceptable at current traffic levels  
- ⚠️ Reduced redundancy should be investigated before weekday traffic resumes

---

## Queries Used
```promql
# Cloudflare tunnel HA connections
cloudflared_tunnel_ha_connections{kubernetes_cluster="somtoday"}

# Request throughput
sum(rate(cloudflared_tunnel_total_requests{kubernetes_cluster="somtoday"}[1h]))

# Request errors
sum(rate(cloudflared_tunnel_request_errors{kubernetes_cluster="somtoday"}[1h]))
```
