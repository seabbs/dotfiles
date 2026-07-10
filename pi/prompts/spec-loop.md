---
description: Spec-driven implement→review→fix loop until the spec is met
argument-hint: "<spec-file>"
---

Run a parent-orchestrated spec-driven implementation loop. You (the parent
session, glm-5.2) are the loop controller and final decision-maker. Child
subagents receive concrete role-specific tasks; they must not run subagents or
manage the loop themselves. Use the `subagent` tool for every delegation.

Default to a maximum of 3 review rounds unless I specify a different cap.
Count a review round each time fresh-context reviewers inspect the diff after a
worker pass. Stop early when the spec is fully satisfied and linting/tests pass.

---

## 1. Read and internalise the spec

- Read the spec file at the path given below (`$@`).
- If the spec references other files (designs, API contracts, existing code,
  configs), read those too before dispatching anything.
- Extract the explicit list of spec requirements. These become the acceptance
  criteria the reviewer checks against.
- Optionally dispatch a `scout` (cheap, deepseek-v4-flash) to map the codebase
  areas the spec touches — relevant files, patterns, constraints, integration
  points. Pass the scout's findings to the implementer so it doesn't have to
  rediscover them.

---

## 2. Implement (prefer cheap workers)

Launch an **async** `weak-worker` (deepseek-v4-flash, cheap) to implement the
spec. Give it:

- The spec contents (inline — fresh-context children don't see conversation
  history) and/or the spec file path.
- The scout's codebase context (files to change, patterns to follow).
- Clear success criteria derived from the spec.
- The constraint: smallest correct change, follow existing patterns, no
  speculative scaffolding, no TODOs.

Use `async: true` so the parent stays unblocked. Use `wait()` when there is no
independent work left and you need the worker's result to continue.

**Model escalation rule:** Prefer `weak-worker` for all implementation. Only
escalate a chunk to `worker` (flagship, glm-5.2) when that chunk requires
complex logic, algorithm implementation, architecture decisions, or
security-sensitive code. If the spec is large, break it into chunks and
dispatch weak-workers sequentially — one writer at a time against the active
worktree.

When the implementation worker completes, treat its handoff as the transition
into review, not as final completion.

---

## 3. Review (fresh context, spec compliance + linting)

After the implementer completes, launch **fresh-context** `reviewer` agents in
**parallel** (`context: "fresh"`, `concurrency: 3`). Each reviewer gets the
spec contents (inline) and a distinct angle. Reviewers must inspect files and
diffs directly — not rely on conversation history — and must NOT edit files.

- **Reviewer 1 — Spec compliance:** Verify every requirement in the spec is
  met by the implementation. Go requirement by requirement. Report which are
  met, partially met, or missing, with file/line evidence.
- **Reviewer 2 — Linting & tests:** Run the project's validation commands
  (`task lint`, `task test`, `R CMD check`, `julia --test`, or
  project-specific equivalents). Report pass/fail with command output. These
  run inside the Docker sandbox automatically — tools route into the
  container, so the toolchain is available without extra wiring.
- **Reviewer 3 — Correctness & maintainability:** Inspect the diff for bugs,
  regressions, edge cases, error handling, and code quality. Return concise
  evidence-backed findings with file/line references.

---

## 4. Synthesise

After reviewers return, synthesise their feedback into:

- **Spec gaps** — requirements not yet met. These are blockers; must be fixed.
- **Lint/test failures** — these are blockers; must be fixed.
- **Optional improvements** — defer unless trivial and safe.
- **Feedback to ignore** — with a short reason.

Do not blindly apply every reviewer suggestion. If reviewers surface an
unapproved product, scope, or architecture decision, pause and ask me before
launching a fix worker.

---

## 5. Fix & loop

- If there are spec gaps or lint/test failures: launch an **async**
  `weak-worker` (or `worker` if the fix needs reasoning) to apply only the
  synthesised fixes. Give it the specific findings, file/line references, and
  the exact spec requirements that are still unmet.
- After the fix worker returns, run another review round (step 3).
- **Max 3 review rounds.** Stop early when all spec requirements are met AND
  linting/tests pass.
- Do not loop for optional polish or speculative improvements.
- If an unapproved decision surfaces at any point, stop and ask me.

---

## 6. Final summary

On completion: inspect the final diff yourself, run or confirm focused
validation, and summarise the loop:

- Rounds run.
- Spec requirements: met / partially met / missing (per requirement).
- Lint/test results.
- Fixes applied.
- Remaining deferred items.
- Why the loop stopped.

---

## Constraints

- One writer at a time against the active worktree. No parallel writes unless
  I explicitly ask for isolated worktrees.
- Use `async: true` for all worker and reviewer launches. Use `wait()` to
  block when there is no independent work left.
- Pass the spec path AND contents to every child — fresh-context children
  don't see conversation history.
- Children must not run subagents or decide the loop outcome.

---

Spec file and any additional focus:

$@
