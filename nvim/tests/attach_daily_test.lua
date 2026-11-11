-- Headless test for config.attach_daily against a throwaway vault.
-- Run: nvim --headless -u NONE -l nvim/tests/attach_daily_test.lua
local here = debug.getinfo(1, "S").source:sub(2):match("(.*/)")
local lazy = vim.fn.stdpath("data") .. "/lazy/"
vim.opt.rtp:prepend(lazy .. "plenary.nvim")
vim.opt.rtp:prepend(lazy .. "obsidian.nvim")
vim.opt.rtp:prepend(here .. "..")

local vault = vim.fn.tempname()
vim.fn.mkdir(vault .. "/dailies", "p")
vim.fn.mkdir(vault .. "/templates", "p")
require("obsidian").setup({
  workspaces = { { name = "t", path = vault } },
  legacy_commands = false,
  daily_notes = { folder = "dailies", date_format = "%Y-%m-%d" },
  preferred_link_style = "wiki",
  ui = { enable = false },
  footer = { enabled = false },
})

local attach = require("config.attach_daily")
local today = vault .. "/dailies/" .. os.date("%Y-%m-%d") .. ".md"
local fails = 0
local function check(name, ok)
  print((ok and "ok   " or "FAIL ") .. name)
  if not ok then fails = fails + 1 end
end
local function read(p)
  local f = io.open(p)
  if not f then return "" end
  local s = f:read("*a")
  f:close()
  return s
end
local function count(s, pat)
  local _, n = s:gsub(pat, "")
  return n
end

local note = vault .. "/my-idea.md"
vim.fn.writefile({ "# My idea", "", "Text." }, note)
vim.cmd("edit " .. vim.fn.fnameescape(note))

attach()
check("creates today's daily note", vim.fn.filereadable(today) == 1)
check("links the note", read(today):find("%[%[my%-idea") ~= nil)

attach()
check("does not link twice", count(read(today), "%[%[my%-idea") == 1)

-- An open daily buffer is edited in place, not behind its back.
vim.cmd("edit " .. vim.fn.fnameescape(today))
local other = vault .. "/second.md"
vim.fn.writefile({ "# Second" }, other)
vim.cmd("edit " .. vim.fn.fnameescape(other))
attach()
local buf = vim.fn.bufnr(today)
local lines = table.concat(vim.api.nvim_buf_get_lines(buf, 0, -1, false), "\n")
check("updates an open daily buffer", lines:find("%[%[second") ~= nil)
check("saves the daily buffer", not vim.bo[buf].modified)

vim.cmd("edit " .. vim.fn.fnameescape(today))
attach()
check("daily note is not linked to itself",
  count(read(today), "%[%[" .. os.date("%Y%-%m%-%d")) == 0)

local outside = vim.fn.tempname() .. ".md"
vim.fn.writefile({ "x" }, outside)
vim.cmd("edit " .. vim.fn.fnameescape(outside))
local before = read(today)
attach()
check("ignores files outside the vault", read(today) == before)

vim.fn.delete(vault, "rf")
print(fails == 0 and "all passed" or (fails .. " failed"))
os.exit(fails == 0 and 0 or 1)
