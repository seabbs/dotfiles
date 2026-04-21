Always respond in UK English

## Instructions & Context
- Refer to and follow all core instructions, identity, and style rules defined in `~/.claude/CLAUDE.md`.
- Custom expert commands are available in `~/.claude/commands/`.

## Identity
- Name: Sam Abbott
- GitHub handle: seabbs
- Bot account: seabbs-bot (signin@samabbott.co.uk)
- Code repositories are in ~/code
- GitHub orgs: cmmid, bristolmathmodellers, TuringLang, epiforecasts, HealthEconomicsHackathon, european-modelling-hubs, JuliaEpi, epinowcast, nfidd, EpiAware

## Git/GitHub
- Never push to main
- Global git identity is seabbs-bot (all commits default to bot)
- Never include "🤖 Generated with [Gemini CLI]", "Co-Authored-By: Gemini", "Co-Authored-By: Happy", or "via [Happy]" in commit messages or PR descriptions
- When creating worktrees do so as a subproject of the current project rather than at a higher dir level
- Use gh CLI to look up repos, create issues, and manage PRs even when not in the source repo (e.g. gh issue create -R seabbs/repo-name)
- Avoid `cd /path &&` before commands — gh works from worktrees without cd, use `git -C` for other repos, and `gh -R` for cross-repo operations
- Commit and push changes before creating PRs
- Create GitHub issues for follow-up work discovered during implementation
- When creating issues or PRs as bot, add a note at the end: "This was opened by a bot. Please ping @seabbs for any questions."
- Run coderabbit review with: coderabbit review --plain
- For line-specific PR review comments use `gh api repos/{owner}/{repo}/pulls/{pr}/comments -f path=file -f body=comment -f commit_id=sha -f line=N -f side=RIGHT`
- When reviewing PRs, fetch inline review comments with `gh api repos/{owner}/{repo}/pulls/{pr}/comments` to see and respond to line-specific feedback

## Workflow
- Use parallel subagents (via `generalist` tool) where possible, activating relevant skills with `activate_skill`.
- Before implementing new features, search codebase for existing similar functionality
- Follow Red/Green TDD: write a failing test, commit, make it pass, commit, refactor, commit
- Commit after each small unit of completed work without waiting to be asked
- Run tests before committing code changes (failing tests are expected for red TDD commits)
- Run the language-standard linter on changed files before committing and fix all issues
- Ask clarifying questions when requirements are ambiguous rather than making assumptions
- If a Taskfile.yml exists, use it for common tasks (build, test, lint, etc.) via the `task` command
- On project setup, create a Taskfile.yml to manage common development tasks
- Skill mapping: R work → lang-r, Julia → lang-julia, Stan → lang-stan, code review → dev-workflow, GitHub issues → github-ops, statistical models → research-academic, academic revision → research-academic, literature → research-academic, verification → dev-workflow, productivity → productivity.
- When reading symlinked files, use the local path within the project (e.g. `context/file.R`) not the resolved target path

## Prose formats (Markdown, Quarto, TeX)
- One sentence per line; no 80-char wrapping
- Use `@placeholder` for missing references

## All languages
- Max 80 chars per line for code
- No trailing whitespace
- No spurious blank lines

## Writing style
- Avoid LLM indicator words: comprehensive, practitioner(s), framework (when vague), current approaches, leverage, facilitate, robust, novel, landscape, utilize, foster, harness, streamline, pivotal, nuanced, multifaceted, cornerstone, synergy, overarching
- Minimise colon use in prose; only use when genuinely needed
- Minimise use of - for punctuation
- Prefer simple, direct prose without adjectives.
