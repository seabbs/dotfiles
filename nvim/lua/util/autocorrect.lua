-- Autocorrect misspelt words in prose as you type, using Vim's spell
-- dictionary without the spell highlighting. A word is corrected when you
-- type the space or punctuation after it. revert() puts back the last
-- correction and adds the word to your spellfile, so it is left alone
-- from then on. Set vim.g.autocorrect = false to switch it off.
local M = {}

local pc = require("util.prose_complete")
local last -- { buf, row, col, from, to }

local function inside_code(before)
  local _, ticks = before:gsub("`", "")
  local _, dollars = before:gsub("%$", "")
  return ticks % 2 == 1 or dollars % 2 == 1 or before:match("%S*://%S*$")
end

-- The correction for the word ending `before`, or nil.
function M.suggest(before)
  local word = before:match("(%a+)$")
  if not word or #word < 3 or inside_code(before) then
    return nil
  end
  local prev = before:sub(1, #before - #word)
  local sentence_start = prev:match("^%s*$") or prev:match("[.!?]%s+$")
  if word:match("^%u") and not sentence_start then
    return nil -- probably a name
  end
  if word:match("^%u+$") then
    return nil -- an acronym
  end
  local bad = vim.spell.check(word)
  if #bad == 0 or bad[1][2] ~= "bad" then
    return nil
  end
  local fix = vim.fn.spellsuggest(word, 1)[1]
  if not fix or fix:find("[%s']") or fix:lower() == word:lower() then
    return nil
  end
  return word, fix
end

local function on_char()
  if vim.g.autocorrect == false or not pc.is_prose(vim.bo.filetype) then
    return
  end
  if not vim.v.char:match("[%s%.,;:!%?%)]") then
    return
  end
  local row, col = unpack(vim.api.nvim_win_get_cursor(0))
  local before = vim.api.nvim_get_current_line():sub(1, col)
  local word, fix = M.suggest(before)
  if not word then
    return
  end
  local buf = vim.api.nvim_get_current_buf()
  local start = col - #word
  -- The buffer is locked during InsertCharPre, so edit once it is free.
  vim.schedule(function()
    local line = vim.api.nvim_buf_get_lines(buf, row - 1, row, false)[1]
    if not line or line:sub(start + 1, col) ~= word then
      return
    end
    vim.api.nvim_buf_set_text(buf, row - 1, start, row - 1, col, { fix })
    if vim.api.nvim_get_current_buf() == buf then
      local cur = vim.api.nvim_win_get_cursor(0)
      if cur[1] == row and cur[2] >= col then
        vim.api.nvim_win_set_cursor(0, { row, cur[2] + #fix - #word })
      end
    end
    last = { buf = buf, row = row, col = start, from = word, to = fix }
  end)
end

-- Undo the last correction and stop correcting that word.
function M.revert()
  if not last or not vim.api.nvim_buf_is_valid(last.buf) then
    return vim.notify("Nothing to revert", vim.log.levels.INFO)
  end
  local l = last
  last = nil
  local line = vim.api.nvim_buf_get_lines(l.buf, l.row - 1, l.row, false)[1]
  if line and line:sub(l.col + 1, l.col + #l.to) == l.to then
    vim.api.nvim_buf_set_text(l.buf, l.row - 1, l.col, l.row - 1, l.col + #l.to, { l.from })
  end
  vim.cmd("silent spellgood " .. vim.fn.fnameescape(l.from))
  vim.notify(("Kept %q and added it to the dictionary"):format(l.from))
end

function M.setup()
  vim.api.nvim_create_autocmd("InsertCharPre", {
    group = vim.api.nvim_create_augroup("autocorrect", { clear = true }),
    callback = on_char,
  })
end

return M
