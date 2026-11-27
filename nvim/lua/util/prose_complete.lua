-- When suggestions appear uninvited. In prose the completion menu opens
-- only after a deliberate trigger (a wiki link, tag or citation), and
-- Copilot is asked for a suggestion only on <Tab> after a word.
local M = {}

M.prose = {
  markdown = true,
  quarto = true,
  rmd = true,
  text = true,
  tex = true,
  plaintex = true,
  typst = true,
  gitcommit = true,
  octo = true,
}

function M.is_prose(ft)
  return M.prose[ft] == true
end

-- `before` is the line up to the cursor.
function M.wants_menu(before)
  return before:match("%[%[[^%]]*$") ~= nil
    or before:match("^#[%w_/%-]*$") ~= nil
    or before:match("%s#[%w_/%-]*$") ~= nil
    or before:match("^@[%w_:%-]*$") ~= nil
    or before:match("[%s%[%(;]@[%w_:%-]*$") ~= nil
end

function M.after_word(before)
  return before:match("%S$") ~= nil
end

-- For blink.cmp's completion.menu.auto_show.
function M.auto_show(ctx)
  if not M.is_prose(vim.bo.filetype) then
    return true
  end
  return M.wants_menu(ctx.line:sub(1, ctx.cursor[2]))
end

return M
