#!/usr/bin/env bash
# One-off migration (2026-06-03): import the open `- [ ]` tasks found across the
# Obsidian vault into Taskwarrior so nothing is lost. Each task keeps a link
# back to its source note via the `note` UDA and is tagged +migrated for review
# (`tw +migrated`). Excluded: one empty checkbox and a pasted covidregionaldata
# CONTRIBUTING template from 2021 (not personal todos).
#
# NB: intended to run ONCE. Re-running creates duplicates.
set -euo pipefail
export TASKRC="${TASKRC:-$HOME/.config/task/taskrc}"
TW="$HOME/.local/share/tw-shim/task"
add() { "$TW" add +migrated "$@"; }

# --- Nowcasting overview / STLT paper -------------------------------------
add project:papers.nowcasting note:dailies/2026-03-16.md \
  Write a first draft for the modelling sections of the STLT nowcasting overview paper
add project:papers.nowcasting note:dailies/2026-03-16.md \
  Go through the nowcasting overview paper and check we can remove commented out sections
add project:papers.nowcasting note:dailies/2026-03-16.md \
  Draft an introduction for the nowcasting overview paper
add project:papers.nowcasting note:dailies/2026-03-16.md \
  Throw in some ideas for nowcasting overview challenges
add project:papers.nowcasting note:dailies/2026-05-11.md \
  Add Sharons changes to nowcasting guide, follow the Charniga et al reporting checklist \
  for example where you report the incubation period report the distribution it was estimated from

# --- epinowcast seminar series --------------------------------------------
add project:epinowcast.seminars note:dailies/2026-04-14.md \
  Add automation for PR creation from a sheet for the epinowcast seminar series
add project:epinowcast.seminars note:dailies/2026-04-14.md \
  Add a mailing list using the RSS feed, trigger when a page is updated and before the seminar at a routine time
add project:epinowcast.seminars note:dailies/2026-04-14.md \
  Look at if we can update how the seminar table is ordered
add project:epinowcast.seminars note:dailies/2026-04-14.md \
  Make signup forms for volunteering yourself or others that creates a github issue
add project:epinowcast.seminars note:dailies/2026-04-14.md \
  Make some kind of seminar theme survey
add project:epinowcast.seminars note:dailies/2026-04-14.md \
  Turn off the epinowcast seminar waiting area

# --- Composable workflow / modelling paper --------------------------------
add project:papers.workflow note:periodic/daily/2026-01-19.md \
  Finalise last workflow comments that dont depend on figures, ready for local work
add project:papers.workflow note:periodic/daily/2026-01-19.md \
  Add conceptual workflow section to workflow draft
add project:papers.workflow note:periodic/daily/2026-01-19.md \
  Make current workflow an implementation guide
add project:papers.workflow note:periodic/daily/2026-01-19.md \
  Add metacompartments for workflow blocks and text framing the steps in them

# --- Reading list ---------------------------------------------------------
add project:epiforecasts +reading note:dailies/2026-04-08.md \
  Read Manuels baseline paper and give comments
add +reading note:dailies/2026-04-22.md \
  Read https://www.jstatsoft.org/article/download/v110i08/4617
add +reading note:dailies/2026-05-01.md \
  Read agent workflow paper
add +reading note:dailies/2026-05-07.md \
  Read Legionnaires paper from Nyall
add +reading note:dailies/2026-05-07.md \
  Read delays paper from Nyall
add +reading note:dailies/2026-05-14.md \
  Look at Sebs LLM evaluation
add project:epiforecasts +reading note:periodic/daily/2026-01-09.md \
  Do the expert review for LLM model construction https://github.com/epiforecasts/llm-epi-composition/tree/main/expert_review

# --- Email / quick --------------------------------------------------------
add +email note:dailies/2026-03-05.md \
  Email Ben Bolker a copy of the paper and say sorry for forgetting
add +email note:dailies/2026-04-29.md \
  Send email introducing Rebecca and UKHSA

# --- epinowcast / forecasting ---------------------------------------------
add project:epinowcast note:dailies/2026-05-01.md \
  Look at suggested epinowcast website text
add project:epiforecasts note:dailies/2026-05-06.md \
  Look at using respicast baselinecast via github

echo "Imported $("$TW" +migrated count) tasks tagged +migrated."
