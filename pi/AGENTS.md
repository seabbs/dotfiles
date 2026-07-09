# Pi — global instructions

This is `~/.pi/agent/AGENTS.md`. Pi loads it as global context for every session.
Directory structure and GitHub-org conventions live in `~/CLAUDE.md` (pi reads
`CLAUDE.md` walking up from cwd) — do not duplicate them here. This file holds
pi-specific guidance: models, subagent usage, and security posture.

## Model strategy

- **Parent session:** `z-ai/glm-5.2` via OpenRouter — 1M-token context, strong
  agentic coding. This is the model that runs the main conversation and all
  heavy reasoning (`thinking: high`).
- **Cheap subagents:** `z-ai/glm-4.7-flash` for recon and gathering roles
  (`scout`, `context-builder`, `researcher`, `delegate`) — these mostly read
  files and fetch sources, so a fast cheap model is plenty.
- **Heavy subagents inherit the parent model:** `planner`, `worker`, `oracle`,
  `reviewer` run on glm-5.2 (deep reasoning, implementation, review).
- **`weak-worker`:** a custom cheap worker on glm-4.7-flash for low-stakes
  tasks — summarisation, simple mechanical edits, scratch scaffolding, bulk
  find-and-replace, docstring churn. Use it instead of `worker` when the task
  is mechanical and doesn't need flagship reasoning. Do NOT use it for logic,
  architecture, or anything where a subtle error is costly.
- **Secondary provider (optional):** an Anthropic subscription is available via
  `/login` (OAuth, no key). Use Ctrl+P to cycle to Claude mid-session. Not
  wired by default; run `/login` and select Anthropic to enable.

## Subagent usage — use extensively

Default to delegating non-trivial work rather than doing it inline. The parent
orchestrates, reviews, and applies fixes as the single writer.

- `scout` — fast codebase recon, writes `context.md` handoff (cheap).
- `context-builder` — structured requirements/codebase handoff (cheap).
- `researcher` — web research briefs, primary sources (cheap).
- `delegate` — lightweight generic delegation (cheap).
- `weak-worker` — mechanical/low-stakes edits and scaffolding (cheap).
- `planner` — implementation plans (flagship).
- `worker` — single-writer implementation, approved handoffs (flagship).
- `oracle` — decision/architecture advisory (flagship).
- `reviewer` — adversarial review-and-fix (flagship).

Patterns:
- **Implementation:** `oracle` advises → `planner` plans → `worker` implements
  → fresh-context `reviewer` inspects → parent synthesises and applies fixes.
- **Research:** parallel `researcher` (external) + `scout` (local), parent
  synthesises.
- **Review:** fresh-context `reviewer`s with distinct angles, parent applies
  only fixes worth doing now.

Rules:
- One writer per repo/worktree. Use fresh-context reviewers, then the parent
  applies fixes — never have several writers in the same tree.
- Child subagents must not launch their own subagents unless explicitly
  assigned a fanout role.
- Keep the fanout small; prefer `context: "fresh"` and pass only what each
  child needs.

## Security posture (auto-mode, minimal interaction)

Pi has **no built-in sandbox**. This setup layers controls so it runs hands-off
without being dangerous:

1. **Guardrails** (`@aliou/pi-guardrails`) — in-process policy on every
   `tool_call` before execution. Allow normal ops inside the workspace;
   **block** (not ask) catastrophic ones (`rm -rf`, `sudo`, `mkfs`), writes to
   `.env`/secrets, and path access outside the workspace. Run
   `/guardrails:onboarding` once, then `/guardrails:settings` to tune. Config
   lives in `~/.pi/agent/extensions/guardrails.json` (machine-local).
2. **Rewind** (`@ayulab/pi-rewind`) — `/rewind` checkpoint navigation so a bad
   agent edit can be undone without manual fixup. The auto-mode safety net.
3. **Container sandbox** (optional, `pi-container-sandbox`) — routes
   read/write/edit/bash into a Docker/Apple container for OS-level isolation.
   Install per-project when blast radius matters. Note: the default image has
   no R/Julia — build a custom image or skip it for R/Julia repos.

`defaultProjectTrust: "always"` skips the project-trust prompt. For genuinely
untrusted repos, run pi inside a container (see pi's Containerization docs)
rather than trusting the project.

## Installed extensions

- **`pi-web-access`** — web search, URL fetching, GitHub repo cloning, PDF/YouTube/video understanding.
- **`pi-subagents`** — subagent delegation (chains, parallel, async). Core to how we work.
- **`@juicesharp/rpiv-todo`** — todo list overlay that survives `/reload` and compaction.
- **`@aliou/pi-guardrails`** — safety policy (see above).
- **`@hypabolic/pi-hypa`** — compresses noisy tool output out of the context window (saves tokens on long sessions and heavy subagent use).
- **`pi-memory`** — durable facts/decisions and a daily log as markdown, surviving compaction and restarts.
- **`@ayulab/pi-rewind`** — `/rewind` checkpoint navigation (see above).
