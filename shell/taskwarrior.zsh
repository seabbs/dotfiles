# Taskwarrior shell integration
# Managed in dotfiles: shell/taskwarrior.zsh -> ~/.config/zsh/taskwarrior.zsh
#
# `task` on PATH is go-task (the Taskfile runner). Taskwarrior ships a binary
# also named `task`, so it is installed keg-only and reached as `tw` here, with
# a PATH shim (~/.local/share/tw-shim) for tools that shell out to `task`
# (e.g. taskwarrior-tui).

export TASKRC="$HOME/.config/task/taskrc"

# Taskwarrior CLI as `tw`
if [ -x "$HOME/.local/share/tw-shim/task" ]; then
  alias tw="$HOME/.local/share/tw-shim/task"
fi

# Interactive TUI (shimmed so its internal `task` calls hit Taskwarrior)
alias twui="$HOME/code/seabbs/dotfiles/scripts/taskwarrior-tui.sh"

# Quick capture: `t <description / attrs>`  ->  tw add ...
t() { tw add "$@"; }
