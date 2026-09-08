-- Options are automatically loaded before lazy.nvim startup
-- Default options that are always set: https://github.com/LazyVim/LazyVim/blob/main/lua/lazyvim/config/options.lua
-- Add any additional options here

-- Set localleader to backslash (default, avoids search conflicts)
vim.g.maplocalleader = "\\"

-- molten-nvim is a :UpdateRemotePlugins remote plugin, so it needs a
-- python3 host with pynvim. Homebrew's python is externally managed and
-- cannot take a pip install, so point the host at a dedicated venv
-- (created by python/setup.sh). Without this molten defines no commands
-- at all and :MoltenInit does not exist.
local nvim_venv = vim.fn.expand("~/.local/share/nvim-venv/bin/python")
if vim.fn.executable(nvim_venv) == 1 then
  vim.g.python3_host_prog = nvim_venv
end

-- Auto-reload files changed outside nvim
vim.opt.autoread = true
vim.opt.updatetime = 250
