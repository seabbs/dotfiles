-- Suggestions are opt-in. Copilot never suggests on its own: <Tab> after
-- a word asks for one, and <Tab> again accepts it. In prose the completion
-- menu opens only after [[, # or @ (see util/prose_complete.lua), and
-- <C-Space> opens it anywhere.
local pc = require("util.prose_complete")

local function copilot()
  local ok, s = pcall(require, "copilot.suggestion")
  return ok and s or nil
end

return {
  {
    "zbirenbaum/copilot.lua",
    opts = {
      suggestion = {
        enabled = true,
        auto_trigger = false,
        hide_during_completion = true,
        keymap = {
          accept = false, -- <Tab>, below
          accept_word = false,
          accept_line = false,
          next = "<M-]>",
          prev = "<M-[>",
          dismiss = "<C-]>",
        },
      },
      panel = {
        enabled = true,
        auto_refresh = false,
        keymap = {
          jump_prev = "[[",
          jump_next = "]]",
          accept = "<CR>",
          refresh = "gr",
          open = "<M-CR>",
        },
      },
      filetypes = {
        yaml = true,
        markdown = true,
        help = false,
        gitcommit = false,
        gitrebase = false,
        ["."] = false,
      },
    },
  },
  {
    "saghen/blink.cmp",
    opts = function(_, opts)
      opts.completion = opts.completion or {}
      opts.completion.menu = opts.completion.menu or {}
      opts.completion.menu.auto_show = pc.auto_show
      opts.keymap = opts.keymap or {}
      opts.keymap["<Tab>"] = {
        "snippet_forward",
        function()
          local s = copilot()
          if s and s.is_visible() then
            LazyVim.create_undo()
            s.accept()
            return true
          end
        end,
        function()
          local s = copilot()
          local col = vim.api.nvim_win_get_cursor(0)[2]
          if s and pc.after_word(vim.api.nvim_get_current_line():sub(1, col)) then
            s.next()
            return true
          end
        end,
        "fallback",
      }
    end,
  },
}
