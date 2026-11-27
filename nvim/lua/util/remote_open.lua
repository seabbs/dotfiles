-- Open a file sent from outside nvim (scripts/open-in-nvim.sh) in an
-- editing window, never in a terminal or floating window.
local M = {}

local function editing_win()
  local cur = vim.api.nvim_get_current_win()
  local function ok(w)
    local buf = vim.api.nvim_win_get_buf(w)
    return vim.api.nvim_win_get_config(w).relative == "" and vim.bo[buf].buftype == ""
  end
  if ok(cur) then
    return cur
  end
  for _, w in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
    if ok(w) then
      return w
    end
  end
end

-- Returns "" so it can be called with --remote-expr.
function M.open(path, line)
  vim.cmd("stopinsert")
  local win = editing_win()
  if win then
    vim.api.nvim_set_current_win(win)
  else
    vim.cmd("leftabove vsplit")
  end
  vim.cmd("edit " .. vim.fn.fnameescape(path))
  if line and line > 0 then
    pcall(vim.api.nvim_win_set_cursor, 0, { line, 0 })
    vim.cmd("normal! zz")
  end
  return ""
end

return M
