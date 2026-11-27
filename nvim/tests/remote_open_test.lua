-- Headless test for util.remote_open.
-- Run: nvim --headless -u NONE -l nvim/tests/remote_open_test.lua
local here = debug.getinfo(1, "S").source:sub(2):match("(.*/)")
vim.opt.rtp:prepend(here .. "..")
local ro = require("util.remote_open")

local fails = 0
local function check(name, ok)
  print((ok and "ok   " or "FAIL ") .. name)
  if not ok then
    fails = fails + 1
  end
end

local dir = vim.fn.tempname()
vim.fn.mkdir(dir, "p")
local a, b = dir .. "/a.md", dir .. "/b.md"
vim.fn.writefile({ "1", "2", "3", "4", "5" }, a)
vim.fn.writefile({ "x" }, b)

-- A code window and a terminal window, with the terminal focused.
vim.cmd("edit " .. vim.fn.fnameescape(b))
local code_win = vim.api.nvim_get_current_win()
vim.cmd("vsplit | terminal")
local term_buf = vim.api.nvim_get_current_buf()

check("returns an empty string", ro.open(a, 4) == "")
check("opens the file", vim.api.nvim_buf_get_name(0) == a)
check("in the code window, not the terminal", vim.api.nvim_get_current_win() == code_win)
check("terminal is untouched", vim.api.nvim_buf_is_valid(term_buf) and #vim.fn.win_findbuf(term_buf) == 1)
check("at the line", vim.api.nvim_win_get_cursor(0)[1] == 4)

-- With only a terminal open, it splits rather than replacing it.
vim.cmd("only")
vim.api.nvim_set_current_buf(term_buf)
ro.open(b, 0)
check("splits when only a terminal is open", vim.api.nvim_buf_get_name(0) == b and #vim.fn.win_findbuf(term_buf) == 1)

vim.fn.delete(dir, "rf")
print(fails == 0 and "all passed" or (fails .. " failed"))
os.exit(fails == 0 and 0 or 1)
