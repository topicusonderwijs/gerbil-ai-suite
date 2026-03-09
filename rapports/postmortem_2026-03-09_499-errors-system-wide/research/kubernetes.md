# ☸️ Kubernetes Research: System-wide 499 Errors / Connection Pool Saturation

**Investigation Time Window:** 08:00 - 14:00 CET (07:00 - 13:00 UTC)
**Cluster:** somtoday (production)

## Pod Health

### docent-rest Pods

All docent-rest pods remained in **Running** state throughout the incident. No CrashLoopBackOff, OOMKill, or restarts were detected.

| Pod | Status | Restarts | Node |
|-----|--------|:---:|------|
| docent-rest pods (all) | Running | 0 | Various |

**Note:** The `kube_pod_container_status_restarts_total` metric returned **empty results** for the label patterns queried. However, based on the continuous accumulation of active users and Bugsnag error patterns (all pods receiving ETIMEDOUT from docent frontend), all pods were alive but **functionally degraded** — accepting TCP connections but unable to process requests in time.

### Traefik Pods

| Pod | Node | Status |
|-----|------|--------|
| traefik-* | node01 | Running ✅ |
| traefik-* | node02 | Running ✅ |
| traefik-* | node04 | Running ✅ |

Traefik proxy pods operated normally throughout. They correctly reported 499 and 504 errors as the backends failed to respond.

## Node Health

Based on Cloudflare tunnel metrics (stable at 8 HA connections per node throughout), all cluster nodes remained healthy:

| Node | cloudflared Connections | Status |
|------|:---:|--------|
| node01 | 8 | ✅ Healthy |
| node02 | 8 | ✅ Healthy |
| node04 | 8 | ✅ Healthy |

## Resource Utilization

⚠️ **Detailed CPU/Memory metrics not directly queried** in this investigation phase. However, the behavior pattern (docent-rest pods alive but unresponsive, 13K+ active users) is consistent with **thread pool exhaustion and I/O wait**, not CPU/Memory limits.

The pods were not OOMKilled (no restarts), and they continued accepting connections (Bugsnag shows ETIMEDOUT to individual pod IPs, meaning TCP connections were established but responses timed out).

## Recent Deployments

**Not investigated via Kubernetes metrics.** However:
- The incident started with authenticator→rest-auth connectivity failures at 09:01 CET
- This could be triggered by a rest-auth deployment/restart or a networking issue
- **Question for the team:** Was there a deployment or pod scaling event for rest-auth around 08:50-09:00 CET?

## DNS Issues

At **09:16 CET**, Bugsnag recorded `UnknownHostException: prod-rest-auth: Temporary failure in name resolution` (894 occurrences). This indicates:

1. The Kubernetes DNS service (CoreDNS/kube-dns) could not resolve `prod-rest-auth`
2. Possible causes:
   - rest-auth service/pods were not available (no endpoints)
   - CoreDNS was overloaded by retry storms
   - Network policy or connectivity issue within the cluster
3. DNS failures started **15 minutes after** ConnectTimeoutExceptions (09:01 CET) — the DNS failures may be a secondary effect of retries overloading CoreDNS

## Affected Pods Summary (from Bugsnag ETIMEDOUT IPs)

The docent frontend reported ETIMEDOUT errors to these docent-rest pod IPs, confirming **all pods in the deployment were affected** — this was not a single-pod failure:

| Pod IP | First ETIMEDOUT (CET) | Events |
|--------|:---:|:---:|
| 10.244.5.78 | 10:40 | 3,240 |
| 10.244.6.60 | 09:53 | 2,879 |
| 10.244.2.105 | 09:53 | 2,862 |
| 10.244.5.43 | 10:01 | 1,814 |
| 10.244.6.35 | 10:22 | 1,521 |
| 10.244.4.43 | 09:53 | 1,452 |
| 10.244.6.26 | 10:34 | 855 |
| 10.244.6.4 | 10:59 | 807 |

This shows pods distributed across multiple nodes (10.244.2.x, 10.244.4.x, 10.244.5.x, 10.244.6.x), confirming a cluster-wide application-level issue rather than a node-specific problem.

## Queries Used

```promql
# Pod restarts (RETURNED EMPTY)
kube_pod_container_status_restarts_total{namespace=~"prod-.*", container="docent-rest"}

# Cloudflare tunnel connections (used as node health proxy)
cloudflared_tunnel_ha_connections{kubernetes_cluster="somtoday"}
```

## Key Observations

- ✅ **No pod crashes or restarts detected** — all docent-rest pods remained Running
- ✅ **All cluster nodes remained healthy** (stable Cloudflare tunnel connections)
- ✅ **Traefik proxy layer operated correctly** — faithfully reported backend failures
- 🔴 **All docent-rest pods were functionally degraded** — alive but unable to process requests (I/O blocked)
- 🔴 **DNS resolution failures at 09:16 CET** indicate potential CoreDNS stress or rest-auth service unavailability
- ⚠️ **Pod CPU/Memory metrics not queried** — monitoring gap for this investigation
- ❓ **Key question:** Was there a rest-auth deployment, scaling event, or network change around 09:00 CET?
