---
description: Plan a patch release from recent issues, then record it as a tracking issue
argument-hint: "[repo, defaults to the current one]"
---

Plan a patch release for `$@` (the current repository if that is empty).

The loop this supports: survey recent issues, agree a batch with me, record it
as a tracking issue, then work through it as normal PRs, and I cut the release
at the end.
You do the first half.
You never tag, publish, or register anything.

You are the loop controller.
Dispatch `weak-worker` subagents for the survey work — reading and classifying
issues is mechanical — several in parallel, one per slice of the issue list.
Keep the judgement about what belongs in a patch for yourself.
Children must not run their own subagents.

---

## 1. Establish where the last release ended

```bash
gh release list --limit 5
git log --oneline "$(git describe --tags --abbrev=0)"..HEAD
```

That commit range matters as much as the issues do.
Anything already merged and unreleased belongs in the notes whether or not it
came from an issue in this batch.

Current version, by project type:

- R package: `Version:` in `DESCRIPTION`; changelog is `NEWS.md`
- Julia package: `version =` in `Project.toml`; released by Registrator+TagBot
- Anything else: the latest git tag

The new version increments the patch component and nothing else.

## 2. Triage recent issues

```bash
gh issue list --state open --limit 60 \
  --json number,title,labels,updatedAt,author
```

A patch release fixes things.
Sort each issue into one of three piles, and be strict about the middle one:

- **In scope**: bug fixes, wrong results, crashes, documentation corrections,
  dependency and CI repairs, internal changes with no user-visible effect.
- **Out of scope**: anything adding a feature, changing an interface, or
  altering documented behaviour. That is a minor release. Say so and leave it
  out rather than quietly widening the patch.
- **Too big**: a fix needing design work or touching a model's structure.
  Name it, exclude it, say why.

Prefer issues that are already understood.
An issue with a diagnosis in the thread is patch material; one still needing
investigation is a research task that happens to be labelled a bug.

## 3. Propose the batch, then stop and wait for me

Report:

- the proposed version and the current one
- in-scope issues in the order they should be done, one sentence each on what
  the fix involves
- what you excluded and why, especially anything you judged minor not patch
- work already merged since the last release, which the notes must cover
- anything you were unsure how to classify

Do not create the tracking issue before I approve.
Do not start fixing anything.

## 4. Record the agreed batch

Once I approve, open one tracking issue titled with the version, e.g.
`Release 1.4.3`, containing:

- **Draft release notes**, grouped the way this project already groups them —
  match the existing `NEWS.md` or previous GitHub releases rather than
  inventing headings. Cover the merged-but-unreleased work as well as the
  planned fixes, and write them as user-facing statements rather than a list
  of issue titles.
- **A checklist**, `- [ ] #123 short description`, in the agreed order.
- **What was deferred**, with reasons, so the decision is recorded.

The notes are a draft on purpose: each merged PR may change its own line, and
I rewrite them at release time.

## 5. Then we work the batch together

Each checklist item is a normal PR: issue, branch or worktree, tests, review.
Tick the box when it merges and keep the notes in the tracking issue current.

The release itself is mine — bumping the version, finalising notes, tagging,
and for Julia commenting `@JuliaRegistrator register`.
Never do those, and never open a version-bump PR unless I ask.
