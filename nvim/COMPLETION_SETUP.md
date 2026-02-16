# AI Completion Setup for Neovim

LazyVim includes LSP-based completion by default. You can add AI-powered completion on top.

## Option 1: GitHub Copilot (Recommended)

**Requirements:**
- GitHub Copilot subscription ($10/month or free for students/OSS maintainers)

**Setup:**
1. The config file is already created: `~/.config/nvim/lua/plugins/copilot.lua`
2. Restart Neovim
3. Run `:Copilot auth` to authenticate with GitHub
4. Start typing and Copilot suggestions appear in grey text
5. Press `Tab` to accept suggestions

**Keybindings:**
- `Tab` - Accept suggestion
- `Alt-]` - Next suggestion
- `Alt-[` - Previous suggestion
- `Ctrl-]` - Dismiss suggestion
- `Alt-Enter` - Open Copilot panel with multiple suggestions

## Option 2: Codeium (Free Alternative)

Free AI completion, similar to Copilot.

Replace `copilot.lua` content with:

```lua
return {
  {
    "Exafunction/codeium.vim",
    event = "BufEnter",
    config = function()
      vim.g.codeium_disable_bindings = 1
      vim.keymap.set("i", "<Tab>", function()
        return vim.fn["codeium#Accept"]()
      end, { expr = true })
      vim.keymap.set("i", "<M-]>", function()
        return vim.fn["codeium#CycleCompletions"](1)
      end, { expr = true })
      vim.keymap.set("i", "<M-[>", function()
        return vim.fn["codeium#CycleCompletions"](-1)
      end, { expr = true })
      vim.keymap.set("i", "<C-]>", function()
        return vim.fn["codeium#Clear"]()
      end, { expr = true })
    end,
  },
}
```

Setup:
1. Restart Neovim
2. Run `:Codeium Auth` to authenticate
3. Completions work automatically

## Option 3: Disable AI Completion

If you prefer only LSP completion (already included in LazyVim):

Delete or rename `~/.config/nvim/lua/plugins/copilot.lua`

## Troubleshooting

**Tab not working:**
- Tab completion might conflict with nvim-cmp
- Try `Alt-]` to cycle through suggestions instead
- Or remap to different keys in the config

**No suggestions appearing:**
- Check you're authenticated: `:Copilot status` or `:Codeium Auth`
- Ensure you're in INSERT mode
- Some filetypes might be disabled in config

**Suggestions too aggressive:**
- Set `auto_trigger = false` in config
- Manually trigger with `Alt-\`
