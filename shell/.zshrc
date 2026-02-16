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
export EDITOR="code --wait"

# PATH configuration
export PATH="$PATH:$HOME/.local/bin:$HOME/.lmstudio/bin:$HOME/.cargo/bin"

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

alias julia-claude="~/code/archive/julia-claude/julia-claude"

# Sync all repos under ~/code to latest default branch
alias sync-repos="$HOME/code/seabbs/dotfiles/scripts/sync-repos.sh"

# GitHub account switching aliases
alias ghbot='gh auth switch --user seabbs-bot'
alias ghme='gh auth switch --user seabbs'
alias dashboard='GH_TOKEN=$(gh auth token --user seabbs) gh dash'
