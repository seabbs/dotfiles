# Homebrew prefix: Apple Silicon, Intel mac, or Linuxbrew
for _brew in /opt/homebrew/bin/brew /usr/local/bin/brew \
  /home/linuxbrew/.linuxbrew/bin/brew; do
  [[ -x "$_brew" ]] && eval "$("$_brew" shellenv)" && break
done
unset _brew

# zsh plugins from Homebrew (guarded so a fresh box doesn't error)
for _p in zsh-autocomplete/zsh-autocomplete.plugin.zsh \
  zsh-autosuggestions/zsh-autosuggestions.zsh; do
  [[ -f "$HOMEBREW_PREFIX/share/$_p" ]] && source "$HOMEBREW_PREFIX/share/$_p"
done
unset _p

# Vi-style line editing (Esc for normal mode, i/a for insert)
bindkey -v
export KEYTIMEOUT=1
bindkey '^L' clear-screen
bindkey -M viins '^A' beginning-of-line
bindkey -M viins '^E' end-of-line
bindkey -M viins '^R' history-incremental-search-backward
bindkey -M viins '^P' up-line-or-history
bindkey -M viins '^N' down-line-or-history

# zsh-autosuggestions accept keys (right-arrow also accepts by default)
# ^F: accept suggestion (falls through to forward-char if none)
# ^Y: accept and execute
bindkey '^F' autosuggest-accept
bindkey '^Y' autosuggest-execute

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

# Tailscale CLI on macOS lives inside the App Store bundle; a symlink
# breaks bundle resolution, so alias to the real path instead.
if [[ "$OSTYPE" == darwin* && -x \
  "/Applications/Tailscale.app/Contents/MacOS/Tailscale" ]]; then
  alias tailscale="/Applications/Tailscale.app/Contents/MacOS/Tailscale"
fi
export EDITOR="nvim"
export JULIA_NUM_THREADS=auto
export JULIA_PROJECT=@.

# Fixed port for human-review (default is random), so an SSH LocalForward
# to archie's Host block in ~/.ssh/config can target it reliably.
export HUMAN_REVIEW_PORT=47474

# PATH configuration — only append dirs that actually exist, so a path that is
# absent on this machine (e.g. an app that isn't installed) never pollutes PATH.
# TinyTeX lives under a different prefix and leaf name per platform; the old
# unconditional macOS path was being appended on Linux, where it never existed.
if [[ "$OSTYPE" == darwin* ]]; then
  _tinyt="$HOME/Library/TinyTeX/bin/universal-darwin"
else
  _tinyt="$HOME/.TinyTeX/bin/x86_64-linux"
fi
for _d in "$HOME/.local/bin" "$HOME/.lmstudio/bin" "$HOME/.cargo/bin" \
          "$HOME/.julia/bin" "$_tinyt"; do
  [[ -d "$_d" && ":$PATH:" != *":$_d:"* ]] && PATH="$PATH:$_d"
done
unset _d _tinyt
export PATH

# >>> juliaup initialize >>>

# !! Contents within this block are managed by juliaup !!

path=("${HOME}/.juliaup/bin" $path)
export PATH
# Tab completion for juliaup and julia channel selection
[ -f "${HOME}/.julia/juliaup/completions/zsh.zsh" ] && source "${HOME}/.julia/juliaup/completions/zsh.zsh"

# <<< juliaup initialize <<<

# juliaup, kept portable. Runs after the managed block, and `path=(x $path)`
# prepends, so this wins over anything juliaup puts back above.
path=("$HOME/.juliaup/bin" $path)
export PATH
# Tab completion for juliaup and julia channel selection
[ -f "$HOME/.julia/juliaup/completions/zsh.zsh" ] &&
  source "$HOME/.julia/juliaup/completions/zsh.zsh"

source ~/.config/zsh/ai-cli-aliases.zsh
source ~/.config/zsh/taskwarrior.zsh
source ~/.config/zsh/qmd.zsh

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

# Brew's btop uses brew's ld.so, which never searches system lib dirs, so it
# cannot find the NVIDIA driver's libnvidia-ml and shows no GPU box. Point it
# at a dir holding only that lib (symlinks into /lib/x86_64-linux-gnu) rather
# than exposing all system libs to brew.
[[ -e "$HOME/.local/lib/btop-gpu/libnvidia-ml.so.1" ]] &&
  alias btop='LD_LIBRARY_PATH="$HOME/.local/lib/btop-gpu" btop'

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

# Agents hub (archie): every interactive shell drops into the persistent
# tmux "home" session, mirroring how ghostty auto-launches tmux locally.
# Guarded to archie only and skipped inside tmux, so it never nests and
# never affects the mac. Works for both ssh and mosh logins.
if [[ -o interactive && -z "$TMUX" && -z "$NO_AUTO_TMUX" \
   && "${HOST%%.*}" == "archie" ]]; then
  tmux new-session -A -s home -c "$HOME/code"
fi

# Added by LM Studio CLI (lms)
# Guarded: only add when the CLI is actually installed, and never add twice.
[[ -d "$HOME/.lmstudio/bin" && ":$PATH:" != *":$HOME/.lmstudio/bin:"* ]] &&
  PATH="$PATH:$HOME/.lmstudio/bin"
# End of LM Studio CLI section

# Final PATH tidy: de-duplicate entries, keeping first-seen order. Sourcing this
# file repeatedly (nested shells, tmux, tooling) no longer grows PATH.
typeset -U path
path=($path)
export PATH
