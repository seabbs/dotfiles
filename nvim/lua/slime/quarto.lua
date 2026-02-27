-- Helper functions for sending Rmd/Quarto code blocks
-- via vim-slime to a tmux REPL pane

local M = {}

local function find_code_block()
  local cursor_line = vim.api.nvim_win_get_cursor(0)[1]
  local lines = vim.api.nvim_buf_get_lines(
    0, 0, -1, false
  )

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

function M.get_code_block()
  local start_line, end_line = find_code_block()

  if not start_line then
    vim.notify(
      "No code block found at cursor",
      vim.log.levels.WARN
    )
    return ""
  end

  local lines = vim.api.nvim_buf_get_lines(
    0, start_line, end_line - 1, false
  )
  return table.concat(lines, "\n")
end

function M.get_code_blocks_to_cursor()
  local cursor_line = vim.api.nvim_win_get_cursor(0)[1]
  local lines = vim.api.nvim_buf_get_lines(
    0, 0, -1, false
  )
  local code_blocks = {}
  local in_block = false
  local block_start = nil
  local current_block = {}

  for i, line in ipairs(lines) do
    if i > cursor_line then break end
    if line:match("^```%{") then
      in_block = true
      block_start = i
      current_block = {}
    elseif line:match("^```%s*$") and in_block then
      in_block = false
      if #current_block > 0 then
        table.insert(
          code_blocks,
          table.concat(current_block, "\n")
        )
      end
    elseif in_block then
      table.insert(current_block, line)
    end
  end

  -- Include partial block if cursor is inside one
  if in_block and #current_block > 0 then
    table.insert(
      code_blocks,
      table.concat(current_block, "\n")
    )
  end

  if #code_blocks == 0 then
    vim.notify(
      "No code blocks found before cursor",
      vim.log.levels.WARN
    )
    return ""
  end

  return table.concat(code_blocks, "\n")
end

function M.get_all_code_blocks()
  local lines = vim.api.nvim_buf_get_lines(
    0, 0, -1, false
  )
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
        table.insert(
          code_blocks,
          table.concat(current_block, "\n")
        )
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
