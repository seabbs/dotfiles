-- Helper functions for sending Literate.jl code blocks
-- via vim-slime to a tmux REPL pane
--
-- Literate.jl format:
--   Lines starting with "# " are markdown
--   Lines starting with "#-" are block separators
--   Everything else is code

local M = {}

local function is_markdown(line)
  return line:match("^#%s") or line:match("^#$")
end

local function is_separator(line)
  return line:match("^#%-")
end

local function is_code(line)
  return not is_markdown(line) and not is_separator(line)
end

-- Find current code block boundaries
-- Blocks are separated by #- lines or markdown sections
function M.get_code_block()
  local cursor_line = vim.api.nvim_win_get_cursor(0)[1]
  local lines = vim.api.nvim_buf_get_lines(
    0, 0, -1, false
  )

  -- Find start: search backwards for separator or
  -- markdown, or start of file
  local start_line = 1
  for i = cursor_line - 1, 1, -1 do
    if is_separator(lines[i]) or is_markdown(lines[i]) then
      start_line = i + 1
      break
    end
  end

  -- Find end: search forwards for separator or
  -- markdown, or end of file
  local end_line = #lines
  for i = cursor_line + 1, #lines do
    if is_separator(lines[i]) or is_markdown(lines[i]) then
      end_line = i - 1
      break
    end
  end

  -- Collect code lines in range (skip blank lines at
  -- edges)
  local code_lines = {}
  for i = start_line, end_line do
    if is_code(lines[i]) then
      table.insert(code_lines, lines[i])
    end
  end

  if #code_lines == 0 then
    vim.notify(
      "No code block found at cursor",
      vim.log.levels.WARN
    )
    return ""
  end

  return table.concat(code_lines, "\n")
end

-- Collect all code blocks in the file
function M.get_all_code_blocks()
  local lines = vim.api.nvim_buf_get_lines(
    0, 0, -1, false
  )
  local code_blocks = {}
  local current_block = {}

  for _, line in ipairs(lines) do
    if is_separator(line) then
      if #current_block > 0 then
        table.insert(
          code_blocks,
          table.concat(current_block, "\n")
        )
        current_block = {}
      end
    elseif is_code(line) then
      table.insert(current_block, line)
    else
      -- Markdown line: flush current block
      if #current_block > 0 then
        table.insert(
          code_blocks,
          table.concat(current_block, "\n")
        )
        current_block = {}
      end
    end
  end

  if #current_block > 0 then
    table.insert(
      code_blocks,
      table.concat(current_block, "\n")
    )
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

-- Collect code blocks up to cursor
function M.get_code_blocks_to_cursor()
  local cursor_line = vim.api.nvim_win_get_cursor(0)[1]
  local lines = vim.api.nvim_buf_get_lines(
    0, 0, -1, false
  )
  local code_blocks = {}
  local current_block = {}

  for i, line in ipairs(lines) do
    if i > cursor_line then break end
    if is_separator(line) then
      if #current_block > 0 then
        table.insert(
          code_blocks,
          table.concat(current_block, "\n")
        )
        current_block = {}
      end
    elseif is_code(line) then
      table.insert(current_block, line)
    else
      if #current_block > 0 then
        table.insert(
          code_blocks,
          table.concat(current_block, "\n")
        )
        current_block = {}
      end
    end
  end

  -- Include partial block at cursor
  if #current_block > 0 then
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

return M
