# 🔥 Postmortem Incident Report: [Title]

**Incident Date:** YYYY-MM-DD  
**Time Window:** HH:MM - HH:MM CET (HH:MM - HH:MM UTC)  
**Affected Systems:** [Components, services, environments]  
**Severity:** [Critical / High / Medium / Low]

---

## 1. Executive Summary

[2-3 sentence summary: What happened, what was the impact, how was it resolved]

---

## 2. Timeline

| Time (CET) | Time (UTC) | Event |
|------------|------------|-------|
| HH:MM | HH:MM | [First indicator of problem] |
| HH:MM | HH:MM | [Escalation or degradation] |
| HH:MM | HH:MM | [Peak impact] |
| HH:MM | HH:MM | [Mitigation started] |
| HH:MM | HH:MM | [Service restored] |

---

## 3. Metrics Analysis

### 3.1 Request Latency

| Timestamp (CET) | Value | Status |
|-----------------|-------|--------|
| [Before incident] | [baseline]ms | ✅ Normal |
| [During incident] | [value]ms | 🔴 Critical |
| [After resolution] | [value]ms | ✅ Normal |

### 3.2 Throughput / Request Rate

| Timestamp (CET) | Requests/sec | Status |
|-----------------|--------------|--------|
| [Before] | [value] | ✅ Normal |
| [During] | [value] | ⚠️/🔴 |
| [After] | [value] | ✅ Normal |

### 3.3 Resource Utilization

| Resource | Before | During | After | Notes |
|----------|--------|--------|-------|-------|
| Thread pools | | | | |
| DB connections | | | | |
| Memory | | | | |
| CPU | | | | |

### 3.4 Active Alerts

| Alert | Time Fired | Time Resolved | Severity |
|-------|------------|---------------|----------|
| | | | |

---

## 4. Root Cause Analysis

### 4.1 Confirmed Contributing Factors

1. **[Factor A]**
   - Evidence: [metric/log reference]
   - Impact: [description]

2. **[Factor B]**
   - Evidence: [metric/log reference]
   - Impact: [description]

### 4.2 Probable Contributing Factors

1. **[Factor]** — [Evidence is suggestive but not conclusive]

### 4.3 Cascade Failure Sequence

```
┌─────────────────────────────────────────────────────────────────┐
│ 1. [Initial trigger]                                            │
└─────────────────────────────────────────────────────────────────┘
                              ↓
┌─────────────────────────────────────────────────────────────────┐
│ 2. [Secondary effect]                                           │
└─────────────────────────────────────────────────────────────────┘
                              ↓
┌─────────────────────────────────────────────────────────────────┐
│ 3. [Tertiary effect / user impact]                              │
└─────────────────────────────────────────────────────────────────┘
```

---

## 5. Error Analysis (Bugsnag)

### 5.1 New Errors During Incident

| Error Class | Message | Count | First Seen |
|-------------|---------|-------|------------|
| | | | |

### 5.2 Relevant Stack Traces

```
[Stack trace excerpt if relevant]
```

### 5.3 Error Correlation

[Analysis of how errors correlate with metrics timeline]

---

## 6. Data Gaps

### Metrics Not Available
- ❌ [Metric name] — [Why it would have been useful]
- ❌ [Metric name] — [Why it would have been useful]

### Logs Not Available
- ❌ [Log source] — [What we could have learned]

### Recommended Additional Monitoring
1. [New metric/log to add]
2. [New alert to configure]

---

## 7. Conclusions

### 7.1 Confirmed ✅
- [Finding supported by direct evidence]
- [Finding supported by direct evidence]

### 7.2 Probable 🔶
- [Finding likely true but evidence is indirect]
- [Finding likely true but evidence is indirect]

### 7.3 Uncertain ❓
- [Open question requiring further investigation]
- [Open question requiring further investigation]

---

## 8. Recommendations

### 8.1 Immediate Actions (This Week)
| Action | Owner | Status |
|--------|-------|--------|
| | | ⬜ |

### 8.2 Short-term Improvements (This Sprint)
| Action | Owner | Status |
|--------|-------|--------|
| | | ⬜ |

### 8.3 Long-term Improvements (Roadmap)
| Action | Owner | Status |
|--------|-------|--------|
| | | ⬜ |

---

## 9. Appendix

### A. Datasources Used
| Source | UID/ID | Purpose |
|--------|--------|---------|
| Prometheus | PBFA97CFB590B2093 | Infrastructure metrics |
| Grafana Cloud Metrics | RU1hwHA4k | Wildfly custom metrics |
| Bugsnag | [project] | Application errors |

### B. Key PromQL Queries Used
```promql
# [Description]
[query]
```

### C. Environment Reference
| Component | Description |
|-----------|-------------|
| | |

---

**Report Generated:** [Date/Time]  
**Analysis Period:** [Start] - [End]  
**Analyst:** [AI-assisted / Human reviewer]
