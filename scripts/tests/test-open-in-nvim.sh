#!/bin/bash
# Tests scripts/open-in-nvim.sh with tmux and nvim stubbed on PATH.
# Usage: test-open-in-nvim.sh [path-to-scripts-dir]
set -uo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
SCRIPT="${1:-$(dirname "$HERE")}/open-in-nvim.sh"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/oin.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT
mkdir -p "$WORK/bin" "$WORK/proj"
touch "$WORK/proj/a.md" "$WORK/proj/b.R"
python3 -c 'import socket,sys; s=socket.socket(socket.AF_UNIX); s.bind(sys.argv[1])' \
  "$WORK/nvim.sock"

# tmux stub: list-panes prints $OIN_PANES; everything is logged.
cat > "$WORK/bin/tmux" <<'EOF'
#!/bin/bash
echo "tmux $*" >> "$OIN_LOG"
[ "$1" = list-panes ] && printf '%b' "${OIN_PANES:-}"
exit 0
EOF
cat > "$WORK/bin/nvim" <<'EOF'
#!/bin/bash
echo "nvim $*" >> "$OIN_LOG"
EOF
chmod +x "$WORK/bin/tmux" "$WORK/bin/nvim"

fail=0
pass() { echo "PASS: $1"; }
bad() { echo "FAIL: $1"; fail=1; }
run() {
  : > "$WORK/log"
  (cd "$WORK/proj" && PATH="$WORK/bin:$PATH" TMUX=x OIN_LOG="$WORK/log" \
    bash "$SCRIPT" "$@" > "$WORK/out" 2>&1)
}
logged() { grep -qF -- "$1" "$WORK/log"; }

pane="%3 1 $WORK/nvim.sock\n"

OIN_PANES="$pane" run a.md:12
logged "nvim --server $WORK/nvim.sock --remote-expr" &&
  logged "open('$WORK/proj/a.md', 12)" &&
  pass "opens in the running nvim at the line" || bad "running nvim: $(cat "$WORK/log")"
logged "tmux select-pane -t %3" && pass "focuses the nvim pane" ||
  bad "no focus: $(cat "$WORK/log")"

OIN_PANES="$pane" run --no-focus b.R
logged "open('$WORK/proj/b.R', 0)" && ! logged "select-pane" &&
  pass "--no-focus leaves focus alone" || bad "--no-focus: $(cat "$WORK/log")"

OIN_PANES="%4 1 $WORK/gone.sock\n" run a.md
logged "tmux split-window" && logged "nvim +1" &&
  pass "stale socket falls back to a split" || bad "stale: $(cat "$WORK/log")"

OIN_PANES="" run a.md:5 b.R
logged "tmux split-window" && logged "+5" && logged "$WORK/proj/b.R" &&
  pass "no nvim opens a split with every file" || bad "split: $(cat "$WORK/log")"

OIN_PANES="$pane" run --split a.md
logged "tmux split-window" && ! logged "--remote-expr" &&
  pass "--split forces a new pane" || bad "--split: $(cat "$WORK/log")"

: > "$WORK/log"
(cd "$WORK/proj" && PATH="$WORK/bin:$PATH" TMUX="" OIN_LOG="$WORK/log" \
  bash "$SCRIPT" a.md > "$WORK/out" 2>&1)
[ $? -ne 0 ] && pass "fails outside tmux" || bad "outside tmux succeeded"

OIN_PANES="$pane" run nope.md
grep -q "no such file" "$WORK/out" && pass "rejects a missing file" ||
  bad "missing file: $(cat "$WORK/out")"

echo
[ "$fail" = 0 ] && echo "ALL PASS" || echo "SOME FAILED"
exit "$fail"
