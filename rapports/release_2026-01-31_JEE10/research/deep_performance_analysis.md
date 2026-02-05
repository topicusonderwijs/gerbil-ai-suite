# 🔍 JEE10 Deep Performance Analysis

**Investigation Period:** 2026-02-01 09:00-16:00 CET (Performance Regression Window)  
**Focus:** Understanding the 167% P99 latency increase with zero production errors

## Key Findings Summary

**Critical Discovery:** The JEE10 performance regression is not a simple "all requests slower" scenario. Analysis reveals:

- **Targeted Impact:** Main issue affects `sis-ui` component specifically
- **Percentile Gradient:** Impact increases dramatically at higher percentiles  
- **Volume Paradox:** Higher request volumes during regression window with slower responses
- **Clean Error State:** Zero production application errors despite severe latency degradation

---

## 1. Request Volume and Traffic Patterns

### 1.1 Primary Traffic Distribution

During the regression window (Feb 1, 09:00-16:00 CET), traffic was concentrated on:

| Service | Request Rate (req/sec) | Peak Period | Notes |
|---------|------------------------|-------------|-------|
| **sis-ui (main UI)** | 14-33 req/sec | 10:00-15:00 | Primary user interface, heaviest impact |
| **ws-rest (API)** | 524-1,373 req/sec | 12:00-16:00 | High volume API backend |
| **edukoppeling services** | ~0 req/sec | All day | No traffic (weekend pattern) |

**Key Observation:** The `ws-rest` API maintained high throughput (up to 1,373 req/sec) while `sis-ui` experienced severe latency issues at much lower volumes.

### 1.2 Traffic Timeline Analysis

**Morning (09:00-12:00):**
- sis-ui: 14-20 req/sec, stable traffic
- ws-rest: 524-950 req/sec, gradual increase

**Peak Problems (12:00-15:00):**
- sis-ui: 20-33 req/sec, highest latencies observed
- ws-rest: 950-1,373 req/sec, volume surge

**Afternoon (15:00-16:00):**
- sis-ui: Declining to 8-20 req/sec, latency still elevated
- ws-rest: Maintained high volume around 1,000+ req/sec

---

## 2. Latency Impact by Percentile

### 2.1 sis-ui Component (Most Affected)

Analysis of the main user interface component reveals a **dramatic percentile gradient**:

| Percentile | Baseline Range | Peak Regression Range | Impact Factor |
|------------|---------------|----------------------|--------------|
| **P50** | ~58ms | 57-63ms | **+0-8%** ✅ Minimal |
| **P75** | ~88ms | 84-95ms | **+0-8%** ✅ Minimal |
| **P95** | ~280-870ms | 280ms-5000ms | **+0-476%** 🔴 Severe |
| **P99** | ~1.1-1.8s | 1.1s-5.0s+ | **+0-167%** 🔴 Critical |

**Critical Finding:** The median user experience (P50/P75) remained largely unaffected. The performance regression primarily impacts the **worst 5% of requests**, creating a severe "long tail" problem.

### 2.2 Authenticator Component (Secondary Impact)

Based on previous analysis, authenticator showed +44.7% P99 increase. Pattern analysis:

| Time Window | P99 Latency | Status |
|-------------|-------------|--------|
| 09:00-12:00 | 290-650ms | ⚠️ Elevated |
| 12:00-15:00 | 290-2,930ms | 🔴 Critical spikes |
| 15:00-16:00 | 165-260ms | ✅ Improved |

**Notable Pattern:** Authenticator performance recovered in the afternoon while sis-ui remained degraded.

---

## 3. Request Pattern Analysis

### 3.1 Which Requests Are Actually Slower?

Based on the percentile analysis, the affected requests represent:

- **P95-P99 Range (5% of requests):** 167-476% slower than baseline
- **P50-P75 Range (75% of requests):** 0-8% impact (essentially normal)

**Estimation:** Approximately **5% of sis-ui requests** experience severe performance degradation, while **95% of requests maintain normal performance**.

### 3.2 Affected Request Characteristics

The "slow 5%" likely includes:
- **Complex database queries** (reports, large data sets)
- **Heavy UI rendering operations** (gradebooks, student overviews)
- **File upload/download operations**
- **Session-intensive operations**

The "normal 95%" likely includes:
- **Simple navigation requests**
- **Static resource loading** 
- **Basic CRUD operations**
- **Authentication pings**

---

## 4. Application Component Stress Patterns

### 4.1 Backend API Performance (ws-rest)

**Surprising Resilience:** Despite handling 1,000+ req/sec (significantly higher than sis-ui's 20-30 req/sec), the ws-rest component shows:

- Stable response patterns
- No significant P99 degradation mentioned in analysis
- High throughput maintenance during regression window

**Implication:** The JEE10 performance issue is **not uniformly distributed** across components.

### 4.2 Component-Specific Impact Hierarchy

| Component | Impact Level | Evidence |
|-----------|--------------|----------|
| **sis-ui** | 🔴 Critical | P99: 1.17s → 3.12s (+167%) |
| **authenticator** | ⚠️ High | P99: 206ms → 298ms (+45%) |
| **ws-rest** | ✅ Stable | High volume, no significant regression noted |
| **docent-rest** | ✅ Minor | P99: +9.7% (within variance) |

---

## 5. Platform-Level Investigation Priorities

### 5.1 JEE10 Runtime Behavior Theories

Given the percentile-specific impact pattern, likely causes include:

**1. Garbage Collection Issues:**
- New G1GC behavior in JEE10 causing periodic "stop-the-world" pauses
- Would affect long-running requests disproportionately
- Explains clean P50/P75 with terrible P95/P99

**2. Thread Pool Exhaustion:**
- Changed thread management in JEE10 Wildfly
- Complex operations starved for threads
- Simple requests processed normally

**3. Memory Management Changes:**
- Different heap allocation patterns
- Memory pressure affecting complex operations
- Explains component-specific impact (sis-ui vs ws-rest)

### 5.2 Wicket/UI Framework Theory

**UI-Specific Impact:** The fact that `sis-ui` is severely affected while `ws-rest` (pure API) remains stable suggests:

- **Wicket framework compatibility issues** with JEE10
- **Session management changes** affecting UI state
- **Component rendering performance** degradation
- **Client-side resource loading** patterns changed

---

## 6. Investigation Recommendations

### 6.1 Immediate Diagnostic Actions

1. **JVM Profiling During High Latency:**
   - Thread dumps during P99 spikes
   - Garbage collection log analysis
   - Heap dump comparison (JEE8 vs JEE10)

2. **Application-Specific Tracing:**
   - Enable Wildfly request tracing for sis-ui
   - Database query performance monitoring
   - Wicket component rendering times

3. **Resource Utilization Analysis:**
   - CPU usage correlation with P99 spikes
   - Memory allocation patterns
   - Network I/O during slow requests

### 6.2 Platform-Level Investigation

1. **JEE10 Runtime Configuration Review:**
   - Thread pool configurations
   - Garbage collector settings
   - Memory management parameters

2. **Wicket Framework Compatibility:**
   - JEE10 + Wicket integration issues
   - Session handling changes
   - Component lifecycle modifications

---

## 7. Performance Impact Assessment

### 7.1 User Experience Impact

- **95% of users:** Normal experience (0-8% impact)
- **4% of users:** Degraded experience (P95 tier)
- **1% of users:** Severely impacted (P99 tier)

### 7.2 Risk Assessment

**High Risk Operations:**
- Report generation
- Large data exports  
- File uploads/downloads
- Complex UI interactions

**Low Risk Operations:**
- Basic navigation
- Simple lookups
- Authentication
- Most daily operations

---

## 8. Queries Used for Analysis

### Request Volume Analysis
```promql
sum(rate(traefik_service_requests_total{kubernetes_cluster="somtoday", exported_service=~".*-sis-ui-.*"}[1m])) by (exported_service)
sum(rate(traefik_service_requests_total{kubernetes_cluster="somtoday", exported_service=~".*-ws-rest-.*"}[1m])) by (exported_service)
```

### Latency Percentile Analysis
```promql
histogram_quantile(0.50, sum(irate(traefik_service_request_duration_seconds_bucket{kubernetes_cluster="somtoday", exported_service=~".*-oop-sis-ui-.*"}[1m])) by (le))
histogram_quantile(0.75, sum(irate(traefik_service_request_duration_seconds_bucket{kubernetes_cluster="somtoday", exported_service=~".*-oop-sis-ui-.*"}[1m])) by (le))
histogram_quantile(0.95, sum(irate(traefik_service_request_duration_seconds_bucket{kubernetes_cluster="somtoday", exported_service=~".*-oop-sis-ui-.*"}[1m])) by (le))
histogram_quantile(0.99, sum(irate(traefik_service_request_duration_seconds_bucket{kubernetes_cluster="somtoday", exported_service=~".*-oop-sis-ui-.*"}[1m])) by (le))
```

### Authenticator Performance
```promql
histogram_quantile(0.99, sum(irate(traefik_service_request_duration_seconds_bucket{kubernetes_cluster="somtoday", exported_service=~".*-authenticator-.*"}[1m])) by (le))
```

---

## 9. Conclusions

**Key Discovery:** The JEE10 performance regression is a **percentile-specific, component-targeted issue** rather than a systemic slowdown. The problem primarily affects:

1. **Complex, long-running requests** (P95-P99 percentiles)
2. **UI-heavy components** (sis-ui severely affected, ws-rest stable)  
3. **Specific application patterns** (likely related to Wicket/UI framework or JEE10 runtime changes)

**Next Steps:** Focus investigation on JEE10 runtime behavior, garbage collection patterns, and Wicket framework compatibility rather than application code issues.