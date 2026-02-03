# Tmuxinator templates

## project.yml

Generic project template for `proj <name>` command.

Creates a session with:
- nvim (left pane, 50%)
- happy (top-right pane, 25%)
- REPL (bottom-right pane, 25%, auto-detects R or Julia)

Usage:
```bash
proj myproject  # Opens ~/code/myproject with full layout
```

## Setup

```bash
mkdir -p ~/.config/tmuxinator
ln -sf ~/code/dotfiles/tmuxinator/project.yml ~/.config/tmuxinator/project.yml
```

Requires [tmuxinator](https://github.com/tmuxinator/tmuxinator):
```bash
brew install tmuxinator
```
