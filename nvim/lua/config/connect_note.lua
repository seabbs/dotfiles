-- Search the vault for a note and link it at the cursor, the way `#`
-- completes tags.
local M = {}

-- Insert a link to the note at `path` after the cursor, with a space
-- before it unless the cursor is already on whitespace.
function M.insert(path)
  local link = require("obsidian.note").from_file(path):format_link()
  local row, col = unpack(vim.api.nvim_win_get_cursor(0))
  local line = vim.api.nvim_get_current_line()
  local at = line:sub(col + 1, col + 1)
  if line ~= "" and not at:match("%s") then
    link = " " .. link
  end
  local pos = line == "" and 0 or col + 1
  vim.api.nvim_buf_set_text(0, row - 1, pos, row - 1, pos, { link })
  vim.api.nvim_win_set_cursor(0, { row, pos + #link - 1 })
end

function M.pick()
  Obsidian.picker.find_notes({
    prompt_title = "Connect note",
    callback = M.insert,
  })
end

return M
