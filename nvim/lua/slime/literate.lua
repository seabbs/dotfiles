-- Helper functions for sending Literate.jl code blocks
-- via vim-slime to a tmux REPL pane
--
-- Literate.jl format:
--   Lines starting with "# " are markdown
--   Lines starting with "#-" are block separators
--   md"""...""" blocks are markdown (triple-quoted)
--   #=...=# blocks are comments
--   Everything else is code

local M = {}

local function is_markdown(line)
  return line:match("^#%s") or line:match("^#$")
end

local function is_separator(line)
  return line:match("^#%-")
end

local function is_md_open(line)
  return line:match('^md"""')
end

local function is_md_close(line)
  return line:match('^"""')
end

local function is_code(line)
  return not is_markdown(line) and not is_separator(line)
end

-- Classify each line, accounting for multi-line blocks:
-- md"""...""" and #=...=#
local function classify_lines(lines)
  local classes = {}
  local in_md_block = false
  local in_comment_block = false
  for i, line in ipairs(lines) do
    if in_md_block then
      classes[i] = "markdown"
      if is_md_close(line) then
        in_md_block = false
      end
    elseif in_comment_block then
      classes[i] = "comment"
      if line:match("=#") then
        in_comment_block = false
      end
    elseif is_md_open(line) then
      classes[i] = "markdown"
      if not line:match('^md""".*"""$') then
        in_md_block = true
      end
    elseif line:match("^#=") then
      classes[i] = "comment"
      if not line:match("=#") then
        in_comment_block = true
      end
    elseif is_separator(line) then
      classes[i] = "separator"
    elseif is_markdown(line) then
      classes[i] = "markdown"
    else
      classes[i] = "code"
    end
  end
  return classes
end

-- Find current code block boundaries
-- Blocks are separated by #- lines or markdown sections
function M.get_code_block()
  local cursor_line = vim.api.nvim_win_get_cursor(0)[1]
  local lines = vim.api.nvim_buf_get_lines(
    0, 0, -1, false
  )
  local classes = classify_lines(lines)

  -- Find start: search backwards for non-code
  local start_line = 1
  for i = cursor_line - 1, 1, -1 do
    if classes[i] ~= "code" then
      start_line = i + 1
      break
    end
  end

  -- Find end: search forwards for non-code
  local end_line = #lines
  for i = cursor_line + 1, #lines do
    if classes[i] ~= "code" then
      end_line = i - 1
      break
    end
  end

  -- Collect code lines in range
  local code_lines = {}
  for i = start_line, end_line do
    if classes[i] == "code" then
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
  local classes = classify_lines(lines)
  local code_blocks = {}
  local current_block = {}

  for i, line in ipairs(lines) do
    if classes[i] == "code" then
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
  local classes = classify_lines(lines)
  local code_blocks = {}
  local current_block = {}

  for i, line in ipairs(lines) do
    if i > cursor_line then break end
    if classes[i] == "code" then
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
