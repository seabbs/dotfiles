-- Headless test for util.autocorrect.
-- Run: nvim --headless -u NONE -l nvim/tests/autocorrect_test.lua
local here = debug.getinfo(1, "S").source:sub(2):match("(.*/)")
vim.opt.rtp:prepend(here .. "..")
vim.opt.spelllang = "en_gb"
vim.opt.spellfile = vim.fn.tempname() .. ".utf-8.add"
local ac = require("util.autocorrect")
ac.setup()

local fails = 0
local function check(name, ok)
  print((ok and "ok   " or "FAIL ") .. name)
  if not ok then
    fails = fails + 1
  end
end

-- Type `text` into a fresh markdown buffer and return the line.
local function typed(text, ft)
  vim.cmd("enew!")
  vim.bo.filetype = ft or "markdown"
  vim.api.nvim_feedkeys("i" .. text, "xt", false)
  vim.wait(50)
  vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<Esc>", true, false, true), "xt", false)
  return vim.api.nvim_get_current_line()
end

check("corrects a typo on space", typed("I saw teh dog ") == "I saw the dog ")
check("corrects before punctuation", typed("I recieve.") == "I receive.")
check("leaves correct words", typed("The colour is fine ") == "The colour is fine ")
check("leaves short words", typed("xq ") == "xq ")
check("leaves capitalised words mid-sentence", typed("ask Abbbott now ") == "ask Abbbott now ")
check("leaves inline code", typed("run `teh x` ") == "run `teh x` ")
check("leaves code files", typed("local teh = 1 ", "lua") == "local teh = 1 ")

-- Revert restores the word and stops it being corrected again.
typed("I saw teh ")
ac.revert()
check("revert restores the typo", vim.api.nvim_get_current_line() == "I saw teh ")
check("reverted word is not corrected again", typed("more teh ") == "more teh ")

vim.g.autocorrect = false
check("can be switched off", typed("I recieve ") == "I recieve ")

print(fails == 0 and "all passed" or (fails .. " failed"))
os.exit(fails == 0 and 0 or 1)
