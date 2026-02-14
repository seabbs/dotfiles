-- Helper functions for sending Rmd/Quarto code blocks to iron.nvim REPL
-- Works with both .rmd and .qmd files

local M = {}

-- Find the current code block boundaries
local function find_code_block()
  local cursor_line = vim.api.nvim_win_get_cursor(0)[1]
  local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)

  -- Find start of code block (search backwards)
  local start_line = nil
  for i = cursor_line, 1, -1 do
    if lines[i]:match("^```%{") then
      start_line = i
      break
    end
  end

  if not start_line then
    return nil
  end

  -- Find end of code block (search forwards)
  local end_line = nil
  for i = cursor_line, #lines do
    if i > start_line and lines[i]:match("^```%s*$") then
      end_line = i
      break
    end
  end

  if not end_line then
    return nil
  end

  return start_line, end_line
end

-- Send current code block to REPL
function M.send_code_block()
  local start_line, end_line = find_code_block()

  if not start_line then
    vim.notify(
      "No code block found at cursor",
      vim.log.levels.WARN
    )
    return ""
  end

  -- Extract lines between the fences (excluding the ``` lines)
  local lines = vim.api.nvim_buf_get_lines(
    0,
    start_line,
    end_line - 1,
    false
  )

  return table.concat(lines, "\n")
end

-- Send all code blocks in the document to REPL
function M.send_all_code_blocks()
  local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
  local code_blocks = {}
  local in_block = false
  local current_block = {}

  for _, line in ipairs(lines) do
    if line:match("^```%{") then
      in_block = true
      current_block = {}
    elseif line:match("^```%s*$") and in_block then
      in_block = false
      if #current_block > 0 then
        table.insert(code_blocks, table.concat(current_block, "\n"))
      end
    elseif in_block then
      table.insert(current_block, line)
    end
  end

  if #code_blocks == 0 then
    vim.notify(
      "No code blocks found in document",
      vim.log.levels.WARN
    )
    return ""
  end

  return table.concat(code_blocks, "\n")
end

return M
