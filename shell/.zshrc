source /opt/homebrew/share/zsh-autocomplete/zsh-autocomplete.plugin.zsh

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

# fzf integration
source <(fzf --zsh)

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

# direnv
eval "$(direnv hook zsh)"

# GitHub account switching aliases
alias ghbot='gh auth switch --user seabbs-bot'
alias ghme='gh auth switch --user seabbs'
alias dashboard='GH_TOKEN=$(gh auth token --user seabbs) gh dash'
