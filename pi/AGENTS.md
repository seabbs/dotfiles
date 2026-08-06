# Pi — global instructions

This is `~/.pi/agent/AGENTS.md`. Pi loads it as global context for every session.
Directory structure and GitHub-org conventions live in `~/CLAUDE.md` (pi reads
`CLAUDE.md` walking up from cwd) — do not duplicate them here. This file holds
pi-specific guidance: models, subagent usage, and security posture.

## Model strategy

- **Parent session:** `openrouter/~deepseek/deepseek-v4-flash-latest` — strong flash-tier
  coding model (leads glm-4.7-flash by ~13 coding-index points), cheap on output
  tokens, with `thinking: high`. This is the model that runs the main conversation,
  all reasoning, and all subagents by default.
- **All subagents inherit the parent model** (`~deepseek/deepseek-v4-flash-latest`):
  `planner`, `worker`, `oracle`, `reviewer` for heavy work, and `scout`,
  `context-builder`, `researcher`, `delegate` for recon — all on the same model
  for simplicity and consistency.
- **`weak-worker`:** explicitly pinned to `openrouter/~deepseek/deepseek-v4-flash-latest`
  with `thinking: high` as a designated cheaper-in-practice agent for low-stakes
  tasks — summarisation, simple mechanical edits, scratch scaffolding, bulk
  find-and-replace, docstring churn. Use it instead of `worker` when the task
  is mechanical and doesn't need the full subagent reasoning pipeline.
- **Secondary provider (optional):** an Anthropic subscription is available via
  `/login` (OAuth, no key). Use Ctrl+P to cycle to Claude mid-session. Not
  wired by default; run `/login` and select Anthropic to enable.
- **Model switching:** `openrouter/~deepseek/deepseek-v4-flash-latest` is in `enabledModels`
  so Ctrl+P cycles to alternative models mid-session (e.g. `glm-5.2` for
  specialised deep-reasoning tasks or `claude-opus-4.8` when Anthropic is needed).

## Dispatch reflex — default to delegation

Do not do inline work that a subagent could do. The parent orchestrates,
reviews, and applies fixes as the single writer. Before writing a multi-file
change, running a multi-step investigation, or editing more than ~1 trivial
file, stop and dispatch. Cost matters: cheap models are fast and plentiful,
flagship models are scarce — match the model to the task, not the other way
around.

### Task-size → model map

| Task shape | Agent | Model | Notes |
|---|---|---|---|
| Codebase recon, "what's where" | `scout` | ~deepseek/deepseek-v4-flash-latest (inherits) | Writes `context.md` handoff. |
| Requirements / structured handoff | `context-builder` | ~deepseek/deepseek-v4-flash-latest (inherits) | Before `planner`/`worker`. |
| Web research, primary sources | `researcher` | ~deepseek/deepseek-v4-flash-latest (inherits) | Pair with local `scout`. |
| Mechanical edits, scaffolding, find-and-replace, docstring churn | `weak-worker` | ~deepseek/deepseek-v4-flash-latest | Explicit pin; NOT for logic/architecture. |
| Lightweight generic delegation | `delegate` | ~deepseek/deepseek-v4-flash-latest (inherits) | When no other fits. |
| Implementation plans | `planner` | ~deepseek/deepseek-v4-flash-latest (inherits) | From a context handoff. |
| Single-writer implementation | `worker` | ~deepseek/deepseek-v4-flash-latest (inherits) | Approved handoffs only. |
| Architecture / decision advice | `oracle` | ~deepseek/deepseek-v4-flash-latest (inherits) | Advisory, doesn't write. |
| Adversarial review + fix | `reviewer` | ~deepseek/deepseek-v4-flash-latest (inherits) | Fresh context, distinct angles. |

### Dispatch patterns

- **Implementation:** `oracle` advises → `planner` plans → `worker`
  implements → fresh-context `reviewer` inspects → parent synthesises and
  applies fixes.
- **Research:** parallel `researcher` (external) + `scout` (local), parent
  synthesises.
- **Review:** fresh-context `reviewer`s with distinct angles, parent applies
  only fixes worth doing now.
- **Mechanical edits (no logic):** `scout` (optional, for recon) →
  `weak-worker` implements → parent verifies with `jq`/`git diff`/test runs.
  This is the cheapest path and the default for wiring, config, and docs.

### Rules

- One writer per repo/worktree. Use fresh-context reviewers, then the parent
  applies fixes — never have several writers in the same tree.
- Child subagents must not launch their own subagents unless explicitly
  assigned a fanout role.
- Keep the fanout small; prefer `context: "fresh"` and pass only what each
  child needs.
- Give each child an exact, self-contained task with file paths and expected
  content — cheap models shine with precise specs, not open-ended asks.
- Verify cheap-agent output yourself before accepting: the parent is the guard
  against silent mistakes. A stale "needs attention" signal does not mean the
  run failed — check `status` before nudging.

## Subagent usage — use extensively

The dispatch-reflex table above is the reference. Agent roster:

- `scout` — fast codebase recon, writes `context.md` handoff (cheap).
- `context-builder` — structured requirements/codebase handoff (cheap).
- `researcher` — web research briefs, primary sources (cheap).
- `delegate` — lightweight generic delegation (cheap).
- `weak-worker` — mechanical/low-stakes edits and scaffolding (cheap).
- `planner` — implementation plans (flagship).
- `worker` — single-writer implementation, approved handoffs (flagship).
- `oracle` — decision/architecture advisory (flagship).
- `reviewer` — adversarial review-and-fix (flagship).

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

## Version control — jj + tuicr

Some repos are **colocated** jj/git (a `.jj` dir beside `.git`). jj is a second
view over the same git history: every git commit is a jj commit and vice versa,
so the git-based PR flow is unchanged and stays primary. jj does NOT read git's
`user.*`; identity comes from `~/.config/jj/config.toml` (the bot account).

### Worktrees stay git — jj is opt-in inside them

Task isolation stays `git worktree`; it is the strong-isolation mechanism, keep
using it. A fresh git worktree has no `.jj`, so jj is unavailable there by
default. Do NOT use `jj workspace` or try to replace worktrees with jj — mixing
jj workspaces with git worktrees is fragile. If you want jj tooling inside a
worktree, run `jj git init --colocate` in it (safe, reversible with `rm -rf .jj`).

### Use jj for shaping history (where a repo is colocated)

Within a single working copy, prefer jj over git plumbing:
- `jj st` / `jj log` — inspect state; there is no staging area, edits are already
  in the working-copy commit `@`.
- `jj describe -m "…"` — set the message on `@`.
- `jj commit -m "…"` — close `@` and start the next change (≈ `git commit`).
- `jj split` — carve one mixed change into clean, reviewable commits.
- `jj undo` — reverse the last operation.

Push/PR stays git + gh: `jj bookmark create feat/x -r @ && jj git push --bookmark
feat/x`, then the normal `gh pr create` flow. Never point a bookmark at `main`.
If a repo is plain git (no `.jj`), use git as normal — do not run `jj git init`.

### Review with tuicr

**tuicr** is where a human reads a diff, not raw `git diff`. It is git-, jj- and
hg-aware. The `pi-tuicr` extension wires it into pi (tmux only).

The TUI is the human's; the CLI is yours. When the human is reviewing your work,
open or find the session and then read their comments — do not review your own
patch in their session or write comments as them:
- `tuicr review list --repo .` — find the session, `active: true` is the live one.
- `tuicr review comments --session <slug>` — read the comments as JSON. Poll
  roughly every 30s while waiting, and re-read before claiming you are done.
- Treat `issue` as blocking, `suggestion` as consider-or-explain, `note` as a
  question to answer, `praise` as no action.

Only when asked to review a patch yourself, add findings with
`tuicr review add --session <slug> --target-file … --line … --type issue
--username pi`, so agent comments stay distinguishable from the human's.

## Installed extensions

- **`pi-web-access`** — web search, URL fetching, GitHub repo cloning, PDF/YouTube/video understanding.
- **`pi-subagents`** — subagent delegation (chains, parallel, async). Core to how we work.
- **`@juicesharp/rpiv-todo`** — todo list overlay that survives `/reload` and compaction.
- **`@aliou/pi-guardrails`** — safety policy (see above).
- **`@hypabolic/pi-hypa`** — compresses noisy tool output out of the context window (saves tokens on long sessions and heavy subagent use).
- **`pi-memory`** — durable facts/decisions and a daily log as markdown, surviving compaction and restarts.
- **`@ayulab/pi-rewind`** — `/rewind` checkpoint navigation (see above).
- **`pi-tuicr`** — opens tuicr for local review and feeds the comments back (see above). Needs tmux.
- **`pi-spine`** — orchestration spine for long-running, multi-day agent batches. Dependency-wave scheduling, parallel git worktrees, reviewer agents, and human integration gates. Use `spine init` per project, then `/spine-plan all`, `/spine pending`, `/spine-status`. See [pi.dev/packages/pi-spine](https://pi.dev/packages/pi-spine).

## On-device search (qmd)

**`qmd`** (tobilu/qmd) is installed globally and wired into Claude Code as an
MCP server (`qmd mcp`). It indexes markdown/docs under `~/.config/qmd/index.yml`
and runs hybrid BM25 + vector + LLM reranking locally. Use it for knowledge
retrieval instead of grepping when the question is semantic ("where do we
configure X") rather than literal. Config in `qmd/` of the dotfiles repo.

## Web search (pi-web-access)

Behavioural config (`workflow`, `summaryModel`) is tracked at
`pi/web-search.json` and symlinked to `~/.pi/web-search.json` so search behaves
the same across machines. Default: `auto-summary` workflow with summaries on
`openrouter/~deepseek/deepseek-v4-flash-latest` (cheap; avoids burning opus on summaries).

**API keys are env-var only** (`OPENAI_API_KEY`, `BRAVE_API_KEY`, `EXA_API_KEY`,
`TAVILY_API_KEY`, `GEMINI_API_KEY`, `PERPLEXITY_API_KEY`) — env vars take
precedence over the config file. Never paste API keys into `web-search.json`:
it's a symlink into the tracked repo and would leak into git.
