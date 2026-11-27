#!/bin/bash
# Checks that gh-notify.sh mutes the right things and, more importantly,
# never mutes a question.
#
# No bats/shellspec harness exists for these scripts, so this stubs `gh`
# and runs gh-notify.sh against the fixture in stub-gh-notify. Verifies:
#
#   1. bot noise is dropped, a human is kept.
#   2. a bot comment that addresses you and asks something survives the
#      mute and is marked ASK.
#   3. the needs-seabbs label makes a thread an ask even when the comment
#      asks nothing, which is the half that does not rely on wording.
#   4. --read marks the muted threads read and never an ask. Marking a
#      question read is how a question goes unanswered.
#   5. a thread whose actor cannot be resolved is shown, not muted.
#   6. --asks and --muted account for everything between them.
#   7. muting is per actor, and sparing a question applies to a muted
#      person just as it does to a muted bot.
#
# Usage: test-gh-notify.sh [path-to-scripts-dir]
#   defaults to the scripts/ directory this file lives under.
set -uo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
SRC_SCRIPTS="${1:-$(dirname "$HERE")}"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/gn-test.XXXXXX")"
[ -n "${GN_TEST_KEEP:-}" ] || trap 'rm -rf "$WORK"' EXIT

mkdir -p "$WORK/bin"
cp "$HERE/stub-gh-notify" "$WORK/bin/gh"
chmod +x "$WORK/bin/gh"
export GN_TEST_CALLS="$WORK/calls.log"
export PATH="$WORK/bin:$PATH"

SCRIPT="$SRC_SCRIPTS/gh-notify.sh"
[ -x "$SCRIPT" ] || { echo "FAIL: $SCRIPT is not executable"; exit 1; }

fail=0
pass() { echo "PASS: $1"; }
bad()  { echo "FAIL: $1"; fail=1; }

run() { : > "$GN_TEST_CALLS"; "$SCRIPT" "$@" 2>&1; }

has()    { grep -q -- "$2" <<< "$1"; }
hasnt()  { ! grep -q -- "$2" <<< "$1"; }

# 1 + 2 + 5: the default view
out="$(run)"
if hasnt "$out" "Noise from the worker"; then
  pass "bot noise is dropped"
else
  bad "bot noise was shown"
fi
if has "$out" "A person said something"; then
  pass "a human is kept"
else
  bad "a human was dropped"
fi
if has "$out" "ASK" && has "$out" "Question about scoring"; then
  pass "a bot question survives the mute, marked ASK"
else
  bad "a bot question was muted"
fi
if has "$out" "Stuck, labelled"; then
  pass "the needs-seabbs label makes an ask without a question"
else
  bad "a labelled ask was muted"
fi
if has "$out" "Nothing has been said yet"; then
  pass "an unresolved actor is shown, not muted"
else
  bad "an unresolved actor was muted"
fi
if has "$out" "4 shown (2 of them asks), 1 muted"; then
  pass "the tally matches the fixture"
else
  bad "unexpected tally: $(tail -1 <<< "$out")"
fi

# 6: --asks and --muted
out="$(run --asks)"
if has "$out" "Question about scoring" && has "$out" "Stuck, labelled" \
  && hasnt "$out" "A person said something"; then
  pass "--asks lists only the questions"
else
  bad "--asks listed the wrong set"
fi

out="$(run --muted)"
if has "$out" "Noise from the worker" \
  && hasnt "$out" "Question about scoring"; then
  pass "--muted lists what was dropped, and no asks"
else
  bad "--muted listed the wrong set"
fi

# 4: --read
out="$(run --read)"
calls="$(cat "$GN_TEST_CALLS")"
if has "$calls" "notifications/threads/1"; then
  pass "--read marks the muted thread read"
else
  bad "--read did not mark the muted thread read"
fi
if hasnt "$calls" "notifications/threads/2" \
  && hasnt "$calls" "notifications/threads/4"; then
  pass "--read never marks an ask read"
else
  bad "--read marked an ask read"
fi
if hasnt "$calls" "notifications/threads/3"; then
  pass "--read leaves a human thread alone"
else
  bad "--read marked a human thread read"
fi

# Muting more than one actor, from the environment. The human in the
# fixture asks you a direct question, so muting them does not hide the
# thread -- it is rescued as an ask, and the line changes from its reason
# to "ASK kaitejohnson". That the marker appears at all is what shows the
# second actor in the list was matched.
out="$(GH_NOTIFY_MUTE="seabbs-bot kaitejohnson" run)"
if has "$out" "ASK kaitejohnson"; then
  pass "a second muted actor is matched, and the mute spares their question"
else
  bad "GH_NOTIFY_MUTE did not take a second actor"
fi

# A bad option is a usage error, not a silent default
if "$SCRIPT" --wat >/dev/null 2>&1; then
  bad "an unknown option was accepted"
else
  [ $? -eq 2 ] && pass "an unknown option exits 2" \
    || bad "an unknown option exited with the wrong code"
fi

echo
if [ "$fail" -eq 0 ]; then
  echo "all gh-notify checks passed"
else
  echo "gh-notify checks FAILED"
fi
exit "$fail"
