# ADR-003: Artifact Output Persistence

**Date:** 2026-02-26  
**Status:** Accepted  
**Deciders:** Gerbil AI Suite team

---

## Context

Generated reports (research files + summaries) must be stored durably. The existing VS Code workflow commits them to the `rapports/` directory in this Git repository. In Kubernetes, additional options exist.

Options considered:

| Option | Description | Pros | Cons |
|---|---|---|---|
| A: Git only | Commit all artifacts to the existing `rapports/` Git repo | Version-controlled; familiar to team; link-shareable | Requires Git push from pod; conflict handling needed |
| B: Slack only | Upload all artifacts as Slack files or message attachments | Zero ops overhead | Not version-controlled; 90-day Slack retention; hard to diff |
| C: Object storage (S3/MinIO) | Write to S3-compatible bucket | Cheap, scalable, no Git conflicts | New service to operate; loses Git history discipline |
| D: Hybrid Git + Slack | Commit to Git, post summary excerpt + link to Slack | Best of both: durable + immediately accessible | Requires Git push infrastructure |

---

## Decision

**Option D: Hybrid Git + Slack**.

- Research files (`research/*.md`) and summary (`summary.md`) are committed to the `rapports/` directory of this repository, preserving the existing naming and structure conventions.
- A Slack message is posted with a summary excerpt and a direct link to the Git commit.
- A Slack file upload is used as a fallback only if Git push fails.

Rationale:
- The team already trusts and uses the Git-based report format (three existing release reports and postmortems as evidence).
- Git provides diff, blame, and history that Slack and S3 do not.
- Slack delivery means no one needs to check the repo; the summary comes to them.
- The fallback handles the rare Git conflict case without losing the artifact.

---

## Consequences

- `gerbil-agent` pod needs a PVC with the cloned repository and a deploy key with write access.
- An `initContainer` (`git-init`) clones/pulls the repo on pod startup.
- A `GitPushService` in the application handles the commit + push + conflict retry logic.
- The deploy key (SSH) is scoped to write access on this repository only.
- If the PVC is lost without a prior Git push (disaster scenario), the in-progress run's data is lost; mitigation: write research files to PVC as soon as they're generated (incremental, not batch).

---

## Review trigger

If Git push conflicts become frequent (e.g., multiple concurrent runs committing) or if artifact storage requirements grow beyond PVC capacity, evaluate migrating to a Git-server-less approach (direct GitHub API file write) or adding a write queue.
