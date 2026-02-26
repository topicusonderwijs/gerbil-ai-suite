# ADR-002: Approval Model

**Date:** 2026-02-26  
**Status:** Accepted  
**Deciders:** Gerbil AI Suite team

---

## Context

The agent executes multiple MCP tool calls during a research workflow (up to ~15 calls per release report). Each call touches production observability systems or code repositories. The operators need visibility and control over what the agent does, but excessive confirmation prompts reduce usability.

Options considered:

| Option | Description |
|---|---|
| A: No approval | Agent executes all tool calls automatically |
| B: Plan-only approval | Approve the plan once; all tool calls execute automatically |
| C: Per-call approval | Approve every individual tool call |
| D: Layered approval | Plan approval + per-call approval + session-wide consent delegation + token-intensive flag |

---

## Decision

**Option D: Layered approval** — as described in [`03-slack-interface.md §4`](../03-slack-interface.md).

Approval levels:
1. **Clarification loop** — before any plan is built, the agent asks questions to clarify ambiguous requests.
2. **Plan approval** — present the full execution plan (phases, tools, estimated token cost) and require operator approval before any tool call is made.
3. **Per-tool-call approval** — each individual MCP call is presented for approval, showing server, tool name, arguments, and estimated token cost.
4. **Session-wide consent** — the operator can approve all remaining tool calls for the current run with a single button click.
5. **Token-intensive flag** — calls estimated above 5k tokens receive an additional warning and cost estimate.
6. **Commit approval** — the final artifact (summary.md) requires approval before being committed to Git.

---

## Consequences

- Maximum operator control; every action is auditable to a specific person.
- Approval log is stored in the run state (Postgres) and forms the compliance audit trail.
- Session-wide consent reduces interaction fatigue for trusted operators without removing the audit trail.
- The `interrupt()` mechanism in LangGraph is used for all approval gates; pod restarts do not lose pending approval states.
- Future: machine-learning-based trust scoring could auto-approve low-risk calls (post-MVP, requires explicit opt-in decision).

---

## Review trigger

If operator feedback indicates approval fatigue is too high (e.g., median operator grants session-wide consent within 2 tool calls), revisit the granularity of the plan-approval gate to include more tool-call details upfront.
