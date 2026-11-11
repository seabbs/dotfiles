-- Autocmds are automatically loaded on the VeryLazy event
-- Default autocmds that are always set: https://github.com/LazyVim/LazyVim/blob/main/lua/lazyvim/config/autocmds.lua
--
-- Add any additional autocmds here
-- with `vim.api.nvim_create_autocmd`
--
-- Or remove existing autocmds by their group name (which is prefixed with `lazyvim_` for the defaults)
-- e.g. vim.api.nvim_del_augroup_by_name("lazyvim_wrap_spell")

-- Treat *.orig files as their underlying type (precompile workflow).
-- e.g. foo.Rmd.orig → rmd, foo.qmd.orig → quarto, foo.R.orig → r
vim.filetype.add({
  pattern = {
    [".*%.orig$"] = function(path)
      local stem = path:match("^(.-)%.orig$")
      local ext = stem and stem:match("%.([^%.]+)$")
      if ext then
        ext = ext:lower()
        if ext == "rmd" then return "rmd"
        elseif ext == "qmd" then return "quarto"
        elseif ext == "r" then return "r"
        end
      end
    end,
  },
})

-- Auto-reload files changed outside of nvim (e.g., by Claude Code)
local autoreload = vim.api.nvim_create_augroup("autoreload", { clear = true })

vim.api.nvim_create_autocmd({ "FocusGained", "BufEnter", "CursorHold", "CursorHoldI" }, {
  group = autoreload,
  pattern = "*",
  callback = function()
    if vim.fn.mode() ~= "c" then
      vim.cmd("checktime")
    end
  end,
})

vim.api.nvim_create_autocmd("FileChangedShellPost", {
  group = autoreload,
  pattern = "*",
  callback = function()
    vim.notify("File changed on disk. Buffer reloaded.", vim.log.levels.WARN)
  end,
})

-- Auto-save when leaving insert mode or changing text
local autosave = vim.api.nvim_create_augroup("autosave", { clear = true })

vim.api.nvim_create_autocmd({ "InsertLeave", "TextChanged" }, {
  group = autosave,
  pattern = "*",
  callback = function()
    if vim.bo.modified and vim.bo.buftype == "" and vim.fn.expand("%") ~= "" then
      vim.cmd("silent! write")
    end
  end,
})

-- Spell checking is opt-in (<leader>us). Keep LazyVim's soft wrap for
-- prose but drop the spell it turns on with it.
pcall(vim.api.nvim_del_augroup_by_name, "lazyvim_wrap_spell")
vim.api.nvim_create_autocmd("FileType", {
  group = vim.api.nvim_create_augroup("prose_wrap", { clear = true }),
  pattern = { "text", "plaintex", "typst", "gitcommit", "markdown" },
  callback = function()
    vim.opt_local.wrap = true
  end,
})

-- Autocorrect in prose, with <M-z> to revert (see util/autocorrect.lua).
require("util.autocorrect").setup()

-- Publish this nvim's server address on its tmux pane, so agents can open
-- files here with scripts/open-in-nvim.sh.
if vim.env.TMUX and vim.env.TMUX_PANE and vim.v.servername ~= "" then
  local pane = vim.env.TMUX_PANE
  vim.fn.jobstart({ "tmux", "set-option", "-p", "-t", pane, "@nvim_server", vim.v.servername })
  vim.api.nvim_create_autocmd("VimLeavePre", {
    group = vim.api.nvim_create_augroup("nvim_server_pane", { clear = true }),
    callback = function()
      vim.fn.system({ "tmux", "set-option", "-p", "-u", "-t", pane, "@nvim_server" })
    end,
  })
end
