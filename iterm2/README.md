# iTerm2 configuration

## Setup

1. Open iTerm2 > Settings > General > Preferences
2. Check "Load preferences from a custom folder or URL"
3. Set path to `~/code/dotfiles/iterm2`
4. Check "Save changes to folder when iTerm2 quits"

## Keybindings

Configure in Settings > Keys > Key Bindings.

These mirror tmux keybindings using Alt (Option) to avoid macOS conflicts.

### Tab navigation

| Shortcut | Action |
|----------|--------|
| `Alt+n` | Next Tab |
| `Alt+p` | Previous Tab |
| `Alt+1-9` | Go to Tab 1-9 (if not in tmux) |

### Pane management

| Shortcut | Action |
|----------|--------|
| `Alt+\|` | Split Horizontally with Current Profile |
| `Alt+-` | Split Vertically with Current Profile |
| `Alt+h` | Select Pane Left |
| `Alt+j` | Select Pane Below |
| `Alt+k` | Select Pane Above |
| `Alt+l` | Select Pane Right |

Note: When inside tmux, Alt keys pass through to tmux which has matching bindings.

### Adding keybindings

1. Settings > Keys > Key Bindings > +
2. Click in "Keyboard Shortcut" field, press the key combo
3. Select Action from dropdown
4. For splits, choose "Split Horizontally/Vertically with Current Profile"
5. For pane navigation, choose "Select Split Pane on Left/Right/Above/Below"
6. For tabs, choose "Next/Previous Tab" or "Select Tab 1-9"

## Tips

- Ensure "Left Option key" is set to "Normal" in Profiles > Keys for Alt to work
- If Option sends special characters, change to "Esc+" in Profiles > Keys
