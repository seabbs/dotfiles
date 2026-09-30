# Cloud agents

What the unattended cloud agents run from. Everything here is tracked so
their behaviour changes by editing this repo, not by editing a routine
through a web form where nobody can see what changed.

    environment/setup.sh     the image: Julia, R, gh, the General registry
    prompts/bot-worker.md    what the worker agent is told to do
    routines/bot-worker.json the routine body, as a template

The routine's own prompt is one line: read `prompts/bot-worker.md` and
follow it. So a change here reaches the next run with no routine edit.

Nothing here needs the `claude/` submodule. A cloud session clones this
repo and may not init submodules, so the agent depends only on `cloud/`
and `scripts/`.

## The account

Routines belong to the **personal** Claude account
(`s.e.abbott12@gmail.com`), which is the one with GitHub connected. archie
is logged into it. The LSHTM account has no GitHub connection and no
routines, and a routine created there fails in a confusing way rather than
an obvious one.

Check before creating anything:

    jq -r '.oauthAccount.emailAddress' ~/.claude.json

## Creating or updating the routine

From a Claude Code session on archie, ask it to create the routine from
`cloud/routines/bot-worker.json`, filling in two placeholders:

- `ENVIRONMENT_ID` — the environment to run in, from the routine API's
  environment list
- `FRESH_UUID` — a new lowercase v4 UUID

Then run it once by hand and read the run log. The first run is what tells
you whether the repo clone, the token and the toolchain are all there. The
`allowed_tools` list includes `Task` for subagents; if the first run cannot
dispatch one, that name is what to check.

## Secrets

**This repo is public.** Nothing here holds a credential, and nothing here
should ever print one.

The agent acts as seabbs-bot and nothing else. Its token reaches the
session as `GH_TOKEN` from the environment's secret store, so it is set
once where the routine runs and never appears in a commit. A fine-grained
PAT limited to the owners in the prompt, with contents, pull requests and
issues write, is enough. It does not need admin, and it cannot merge
anything.

Because the repo is public, the prompt is public too. Anyone can read how
to get the agent's attention. That is the reason the trigger rules are
mechanical rather than a matter of judgement: only Sam's comments are
instructions, the mention has to start a line, and the checks live in
`scripts/bot-tasks-scan.sh` where they can be read and tested. Treat a PR
to this repo that edits the prompt or that script as a change to what the
bot is allowed to do.

## Schedule

Four runs a day, at 00:00, 06:00, 12:00 and 18:00 UTC. The routine API's
minimum interval is one hour, so a faster poll is not schedulable. For work
that should be picked up sooner, attach a GitHub webhook trigger to the
same routine so an event fires it directly, and leave the cron as the
sweep that catches whatever the webhook missed.
