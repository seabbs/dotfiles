# Tmux configuration

## tmux.conf

Main tmux configuration with:
- True colour support
- Mouse enabled
- Windows/panes start at 1
- Pane titles in borders
- Vim-style navigation

**Key bindings:**
- `Ctrl-b r` - Reload config
- `Ctrl-b |` - Split horizontal
- `Ctrl-b -` - Split vertical
- `Ctrl-b h/j/k/l` - Vim-style pane navigation
- `Ctrl-b s` - Session picker
- `Ctrl-b w` - Window/session tree

## Setup

```bash
ln -sf ~/code/dotfiles/tmux/tmux.conf ~/.tmux.conf
```
