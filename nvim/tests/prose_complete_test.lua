-- Headless test for util.prose_complete.
-- Run: nvim --headless -u NONE -l nvim/tests/prose_complete_test.lua
local here = debug.getinfo(1, "S").source:sub(2):match("(.*/)")
vim.opt.rtp:prepend(here .. "..")
local pc = require("util.prose_complete")

local fails = 0
local function check(name, ok)
  print((ok and "ok   " or "FAIL ") .. name)
  if not ok then
    fails = fails + 1
  end
end

check("markdown is prose", pc.is_prose("markdown"))
check("quarto is prose", pc.is_prose("quarto"))
check("lua is not prose", not pc.is_prose("lua"))

check("plain words do not open the menu", not pc.wants_menu("Some words"))
check("wiki link opens the menu", pc.wants_menu("See [[my-no"))
check("closed wiki link does not", not pc.wants_menu("See [[note]] and"))
check("tag opens the menu", pc.wants_menu("Ideas #res"))
check("bare hash opens the menu", pc.wants_menu("Ideas #"))
check("heading does not", not pc.wants_menu("## Heading"))
check("hash inside a word does not", not pc.wants_menu("issue#12"))
check("citation opens the menu", pc.wants_menu("as shown by @abbott"))
check("email does not", not pc.wants_menu("mail me at sam@exa"))

check("after a word asks copilot", pc.after_word("x = foo"))
check("at line start does not", not pc.after_word("    "))
check("after a space does not", not pc.after_word("foo "))
check("empty line does not", not pc.after_word(""))

print(fails == 0 and "all passed" or (fails .. " failed"))
os.exit(fails == 0 and 0 or 1)
