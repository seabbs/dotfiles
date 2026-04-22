source /opt/homebrew/share/zsh-autocomplete/zsh-autocomplete.plugin.zsh
bindkey '^L' clear-screen

# Shell options
setopt HIST_IGNORE_DUPS
setopt HIST_IGNORE_SPACE
setopt SHARE_HISTORY
setopt AUTO_CD
setopt CORRECT
setopt EXTENDED_GLOB

eval "$(starship init zsh)"
alias python=python3
alias pip=pip3
alias R=radian
export EDITOR="nvim"
export JULIA_NUM_THREADS=auto
export JULIA_PROJECT=@.

# PATH configuration
export PATH="$PATH:$HOME/.local/bin:$HOME/.lmstudio/bin:$HOME/.cargo/bin:$HOME/.julia/bin:$HOME/Library/TinyTeX/bin/universal-darwin"

# >>> juliaup initialize >>>
# !! Contents within this block are managed by juliaup !!
path=("$HOME/.juliaup/bin" $path)
export PATH
# <<< juliaup initialize <<<

source ~/.config/zsh/ai-cli-aliases.zsh

# fzf integration (kept for piping: cmd | fzf)
source <(fzf --zsh)

# television shell integration (overrides fzf Ctrl+T/R
# with context-aware channel picker and history search)
eval "$(tv init zsh)"

# zoxide integration
eval "$(zoxide init zsh)"

# Resolve dotfiles location from this symlinked .zshrc
DOTFILES="$(dirname "$(readlink -f ~/.zshrc)")"
DOTFILES="$(cd "$DOTFILES/.." && pwd)"

# Sync all repos under ~/code to latest default branch
alias sync-repos="$DOTFILES/scripts/sync-repos.sh"
alias job-status="bash $DOTFILES/scripts/job-status.sh"
alias cat="bat --paging=never"
alias catp="bat"

# Benchmark one or two scripts (auto-detects R/Julia/Python)
bench() {
  _bench_cmd() {
    case "$1" in
      *.R|*.r) echo "Rscript $1" ;;
      *.jl) echo "julia --project=. $1" ;;
      *.py) echo "python3 $1" ;;
      *) echo "$1" ;;
    esac
  }
  local args=("$(_bench_cmd "$1")")
  [ -n "$2" ] && args+=("$(_bench_cmd "$2")")
  hyperfine --warmup 1 "${args[@]}"
}

# Keep the Mac awake for N hours (default 1). Accepts fractional hours.
awake() {
  local hours=${1:-1}
  local seconds
  seconds=$(awk -v h="$hours" 'BEGIN { printf "%d", h * 3600 }')
  echo "Staying awake for ${hours}h (${seconds}s)…"
  caffeinate -t "$seconds"
}
alias asleep='pkill caffeinate'

# direnv
eval "$(direnv hook zsh)"

# GitHub account switching aliases
alias ghbot='gh auth switch --user seabbs-bot'
alias ghme='gh auth switch --user seabbs'
alias dashboard='GH_TOKEN=$(gh auth token --user seabbs) gh dash'

# Added by LM Studio CLI (lms)
export PATH="$PATH:/Users/lshsa2/.lmstudio/bin"
# End of LM Studio CLI section

