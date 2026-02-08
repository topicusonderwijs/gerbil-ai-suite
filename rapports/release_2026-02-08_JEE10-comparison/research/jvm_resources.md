# 💾 JVM Resources Research: JEE10 Weekend Comparison

**Comparison Window:** Feb 7, 2026 vs Jan 24, 2026 (Saturday 12:00 CET)
**Source:** Grafana/Prometheus

---

## Thread Utilization (max %)

| Component | Jan 24 (JEE8) | Feb 7 (JEE10) | Delta | Status |
|-----------|---------------|---------------|-------|--------|
| sis-ui | 2.22% | 2.22% | 0 | ✅ Same |
| ws-rest | 5.56% | 6.67% | +1.11pp | ✅ Normal |
| authenticator | 1.67% | 3.33% | +1.67pp | ⚠️ Slightly higher |
| docent-rest | 2.22% | 2.22% | 0 | ✅ Same |
| rest-auth | 2.22% | 1.11% | -1.11pp | ✅ Lower |
| connect-rest | 0% | 0% | 0 | ✅ Idle |
| mmp-rest | 0% | *(not reporting)* | — | ❓ Missing |
| sis-services | 0% | 2.22% | +2.22pp | ⚠️ New activity |
| accountbeheer | 0% | 0% | 0 | ✅ Same |
| sis-ui-landelijk | 0% | 0% | 0 | ✅ Same |

### Thread Utilization Analysis

- All components remain well below critical thresholds (typically >50%)
- **Authenticator** shows a slight increase in thread usage (+1.67pp), consistent with its P99 latency regression
- **mmp-rest** stopped reporting on Feb 7 — may have been descaled or is not running
- **sis-services** shows new thread activity — possibly processing background tasks

---

## Heap Memory Usage (max %)

| Component | Jan 24 (JEE8) | Feb 7 (JEE10) | Delta | Status |
|-----------|---------------|---------------|-------|--------|
| **sis-ui** | 69.2% | **11.5%** | **-57.7pp** | ✅ 🎉 Major improvement |
| **authenticator** | 61.8% | **11.0%** | **-50.7pp** | ✅ 🎉 Major improvement |
| **ws-rest** | 81.3% | 76.7% | -4.6pp | ✅ Slight improvement |
| **docent-rest** | 68.7% | 40.3% | **-28.4pp** | ✅ Significant improvement |
| **connect-rest** | 59.2% | 22.5% | **-36.6pp** | ✅ Significant improvement |
| **rest-auth** | 71.9% | 35.9% | **-36.0pp** | ✅ Significant improvement |
| **sis-ui-landelijk** | 33.5% | 9.8% | -23.7pp | ✅ Major improvement |
| **sis-services** | 26.2% | 36.5% | +10.2pp | ⚠️ Increase |
| **accountbeheer** | 8.5% | 15.9% | +7.4pp | ⚠️ Increase |

### 🎉 Heap Memory — Critical Finding

**JEE10 shows dramatically lower heap memory usage across almost all components.** This is one of the most positive findings of this comparison:

| Component | Reduction |
|-----------|-----------|
| sis-ui | **83% less heap usage** (69% → 11.5%) |
| authenticator | **82% less heap usage** (62% → 11%) |
| docent-rest | **41% less heap usage** (69% → 40%) |
| connect-rest | **62% less heap usage** (59% → 22.5%) |
| rest-auth | **50% less heap usage** (72% → 36%) |

**Possible explanations:**
1. **JEE10 runtime improvements** — Jakarta EE 10 and newer WildFly use more efficient memory allocation
2. **Lower traffic** — Feb 7 had ~50% less traffic, naturally reducing heap pressure
3. **GC improvements** — JEE10 may use updated GC algorithms that compact heap more effectively
4. **Class loading changes** — Jakarta namespace migration may reduce class metadata overhead

**Note:** Even accounting for 50% less traffic, the heap reduction (up to 83%) far exceeds what traffic reduction alone would explain. This appears to be a genuine JEE10 platform improvement.

**Exceptions:** `sis-services` (+10.2pp) and `accountbeheer` (+7.4pp) show modest increases. These may be processing different workloads or utilizing new JEE10 features.

---

## Key Observations

- ✅ Thread utilization healthy across all components (<10%)
- ✅ **Heap memory dramatically reduced** under JEE10 — major platform benefit
- ⚠️ Authenticator thread usage slightly elevated — correlates with P99 regression
- ❓ mmp-rest not reporting — may need investigation

---

## Queries Used
```promql
# Thread utilization (max %)
max((wildfly_io_busy_task_thread_count{kubernetes_cluster="somtoday", environment="productie"} + wildfly_io_queue_size{kubernetes_cluster="somtoday", environment="productie"}) / wildfly_io_max_pool_size{kubernetes_cluster="somtoday", environment="productie"}) by (component) * 100

# Heap memory usage (max %)
max(base_memory_usedHeap_bytes{kubernetes_cluster="somtoday", environment="productie"} / base_memory_maxHeap_bytes{kubernetes_cluster="somtoday", environment="productie"}) by (component) * 100
```
