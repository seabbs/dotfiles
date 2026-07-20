-- Turn a TODO-style comment into a GitHub issue, then link the comment back
-- to the issue it created.
--
-- Convention:
--   TODO: make the parser handle nested quotes     <- unlinked, actionable
--   TODO(#42): make the parser handle nested quotes <- linked, leave alone
--
-- The linked form is what makes this round-trip: a comment carrying an issue
-- number is already tracked, so batch scans skip it.

local M = {}

-- Keywords todo-comments.nvim highlights by default, plus the label each one
-- should get on GitHub.
M.labels = {
  TODO = nil,
  FIX = "bug",
  FIXME = "bug",
  BUG = "bug",
  HACK = "tech-debt",
  PERF = "performance",
  WARN = nil,
  NOTE = nil,
  TEST = "tests",
}

local KEYWORDS = "TODO|FIX|FIXME|BUG|HACK|WARN|PERF|NOTE|TEST"

-- Closing delimiters of block comments, which would otherwise be swallowed
-- into the issue title (e.g. `<!-- TODO: fix intro -->` in markdown).
local CLOSERS = { "%-%->$", "%*/$", "%-%-}}$", '"""$' }

local function strip_closer(text)
  text = vim.trim(text)
  for _, closer in ipairs(CLOSERS) do
    local stripped = text:gsub("%s*" .. closer, "")
    if stripped ~= text then
      return vim.trim(stripped)
    end
  end
  return text
end

-- Match `KEYWORD:` or `KEYWORD(anything):` and capture the trailing text.
-- Lua patterns have no alternation, so try each keyword in turn.
function M.parse(line)
  for keyword in KEYWORDS:gmatch("[^|]+") do
    local ref, text = line:match(keyword .. "%(([^)]*)%)%s*:?%s*(.*)$")
    if ref then
      return { keyword = keyword, ref = ref, text = strip_closer(text) }
    end
    text = line:match(keyword .. "%s*:%s*(.*)$")
    if text then
      return { keyword = keyword, ref = nil, text = strip_closer(text) }
    end
  end
  return nil
end

-- True when the comment already points at an issue, e.g. TODO(#42).
function M.is_linked(todo)
  return todo.ref ~= nil and todo.ref:match("^#%d+$") ~= nil
end

-- Comment leader for the cursor position, not just the buffer. In a Quarto or
-- markdown file the buffer commentstring is `<!-- %s -->`, but inside an R or
-- Python chunk it should be `#` — ts-context-commentstring knows which.
local function commentstring()
  local ok, ctx = pcall(require, "ts_context_commentstring.internal")
  if ok then
    local cs = ctx.calculate_commentstring()
    if cs and cs ~= "" then
      return cs
    end
  end
  local cs = vim.bo.commentstring
  return (cs ~= "" and cs) or "# %s"
end

-- Open a correctly-delimited TODO comment below the cursor and drop into
-- insert mode with the cursor after the colon, inside any closing delimiter.
function M.insert(keyword)
  keyword = keyword or "TODO"

  local prefix, suffix = commentstring():match("^(.-)%%s(.-)$")
  if not prefix then
    prefix, suffix = "# ", ""
  end

  local lnum = vim.api.nvim_win_get_cursor(0)[1]
  local current = vim.api.nvim_buf_get_lines(0, lnum - 1, lnum, false)[1] or ""
  local indent = current:match("^%s*") or ""

  local head = indent .. prefix .. keyword .. ": "
  vim.api.nvim_buf_set_lines(0, lnum, lnum, false, { head .. suffix })
  vim.api.nvim_win_set_cursor(0, { lnum + 1, #head })
  vim.cmd("startinsert")
end

-- Same, but choose the keyword first.
function M.insert_pick()
  local keywords = { "TODO", "FIXME", "BUG", "HACK", "PERF", "NOTE", "TEST" }
  vim.ui.select(keywords, { prompt = "Comment type" }, function(choice)
    if choice then
      M.insert(choice)
    end
  end)
end

local function gh_env()
  return vim.tbl_extend("force", vim.fn.environ(), {
    GH_TOKEN = vim.trim(vim.fn.system("gh auth token --user seabbs")),
  })
end

local function repo_root()
  local out = vim.fn.systemlist({ "git", "rev-parse", "--show-toplevel" })
  if vim.v.shell_error ~= 0 then
    return nil
  end
  return out[1]
end

-- Permalink to the exact line, pinned to the pushed commit so it does not rot
-- as the file moves. Falls back to nil outside a repo or with no upstream.
local function permalink(path, lnum)
  local root = repo_root()
  if not root then
    return nil
  end

  -- Same pinned token as the create call, so repo resolution cannot disagree
  -- with issue creation when the active gh account differs.
  local res = vim
    .system({
      "gh",
      "repo",
      "view",
      "--json",
      "nameWithOwner",
      "-q",
      ".nameWithOwner",
    }, { env = gh_env(), text = true })
    :wait()
  if res.code ~= 0 then
    return nil
  end
  local nwo = vim.trim(res.stdout or "")

  -- Use the last commit that is actually on the remote; linking to an
  -- unpushed local sha produces a 404.
  local sha = vim.fn.system({
    "git",
    "rev-parse",
    "@{upstream}",
  })
  if vim.v.shell_error ~= 0 then
    sha = vim.fn.system({ "git", "rev-parse", "HEAD" })
    if vim.v.shell_error ~= 0 then
      return nil
    end
  end
  sha = vim.trim(sha)

  local rel = path:sub(#root + 2)
  return ("https://github.com/%s/blob/%s/%s#L%d"):format(nwo, sha, rel, lnum)
end

-- A few lines either side of the TODO, as a fenced block, so the issue is
-- readable without opening the file.
local function context_block(bufnr, lnum, radius)
  local first = math.max(0, lnum - radius - 1)
  local last = math.min(vim.api.nvim_buf_line_count(bufnr), lnum + radius)
  local lines = vim.api.nvim_buf_get_lines(bufnr, first, last, false)
  local ft = vim.bo[bufnr].filetype
  return table.concat({
    "```" .. (ft ~= "" and ft or ""),
    table.concat(lines, "\n"),
    "```",
  }, "\n")
end

-- Rewrite `TODO:` / `TODO(x):` in place as `TODO(#N):`, preserving whatever
-- indentation and comment leader the line already has.
local function link_line(bufnr, lnum, keyword, number)
  local line = vim.api.nvim_buf_get_lines(bufnr, lnum - 1, lnum, false)[1]
  local linked = line:gsub(keyword .. "%([^)]*%)%s*:?", ("%s(#%d):"):format(keyword, number), 1)
  if linked == line then
    linked = line:gsub(keyword .. "%s*:", ("%s(#%d):"):format(keyword, number), 1)
  end
  vim.api.nvim_buf_set_lines(bufnr, lnum - 1, lnum, false, { linked })
end

-- Create an issue from the TODO on the cursor line.
function M.create()
  local bufnr = vim.api.nvim_get_current_buf()
  local lnum = vim.api.nvim_win_get_cursor(0)[1]
  local line = vim.api.nvim_buf_get_lines(bufnr, lnum - 1, lnum, false)[1]

  local todo = M.parse(line)
  if not todo then
    vim.notify("No TODO comment on this line", vim.log.levels.WARN)
    return
  end
  if M.is_linked(todo) then
    vim.notify(("Already tracked as %s"):format(todo.ref), vim.log.levels.INFO)
    return
  end
  if todo.text == "" then
    vim.notify("TODO has no description", vim.log.levels.WARN)
    return
  end

  local path = vim.api.nvim_buf_get_name(bufnr)
  local link = permalink(path, lnum)

  local body = { todo.text, "", context_block(bufnr, lnum, 4) }
  if link then
    table.insert(body, "")
    table.insert(body, ("Source: %s"):format(link))
  end

  local cmd = {
    "gh",
    "issue",
    "create",
    "--title",
    ("%s: %s"):format(todo.keyword, todo.text),
    "--body",
    table.concat(body, "\n"),
  }
  local label = M.labels[todo.keyword]
  if label then
    vim.list_extend(cmd, { "--label", label })
  end

  vim.notify(("Creating issue from %s..."):format(todo.keyword))
  vim.system(cmd, { env = gh_env(), text = true }, function(res)
    vim.schedule(function()
      if res.code ~= 0 then
        vim.notify("gh issue create failed:\n" .. (res.stderr or ""), vim.log.levels.ERROR)
        return
      end
      local url = vim.trim(res.stdout or "")
      local number = tonumber(url:match("/issues/(%d+)"))
      if not number then
        vim.notify("Created: " .. url)
        return
      end
      link_line(bufnr, lnum, todo.keyword, number)
      vim.fn.setreg("+", url)
      vim.notify(("Created #%d (url copied)\n%s"):format(number, url))
    end)
  end)
end

-- Every unlinked TODO in the repo, as quickfix entries. This is the handoff
-- point for an agent: run it, then :cdo or feed the list to Claude.
function M.list_unlinked()
  local root = repo_root()
  if not root then
    vim.notify("Not in a git repo", vim.log.levels.WARN)
    return
  end

  -- Match a keyword followed by `:` or `(` where the parens are not `(#N)`.
  local pattern = ("\\b(%s)(\\((?!#\\d+\\))[^)]*\\))?:"):format(KEYWORDS:gsub("|", "|"))
  local res = vim
    .system({
      "rg",
      "--vimgrep",
      "--pcre2",
      "--no-heading",
      pattern,
      root,
    }, { text = true })
    :wait()

  if res.code ~= 0 and res.code ~= 1 then
    vim.notify("rg failed:\n" .. (res.stderr or ""), vim.log.levels.ERROR)
    return
  end

  local items = {}
  for entry in (res.stdout or ""):gmatch("[^\n]+") do
    local file, lnum, col, text = entry:match("^(.-):(%d+):(%d+):(.*)$")
    if file then
      table.insert(items, {
        filename = file,
        lnum = tonumber(lnum),
        col = tonumber(col),
        text = vim.trim(text),
      })
    end
  end

  if #items == 0 then
    vim.notify("No unlinked TODOs", vim.log.levels.INFO)
    return
  end

  vim.fn.setqflist({}, " ", { title = "Unlinked TODOs", items = items })
  vim.cmd("copen")
  vim.notify(("%d unlinked TODOs"):format(#items))
end

-- @-mention every unlinked TODO into Claude Code, for triage in bulk rather
-- than one keypress at a time. Claude gets the real file/line refs, so it can
-- read surrounding code instead of working from a pasted excerpt.
function M.send_to_claude()
  M.list_unlinked()
  local items = vim.fn.getqflist()
  if #items == 0 then
    return
  end

  local ok, claude = pcall(require, "claudecode")
  if not ok then
    vim.notify("claudecode.nvim not available", vim.log.levels.ERROR)
    return
  end

  for _, item in ipairs(items) do
    local name = vim.api.nvim_buf_get_name(item.bufnr)
    if name ~= "" then
      -- send_at_mention takes 0-indexed lines.
      claude.send_at_mention(name, item.lnum - 1, item.lnum - 1, "TodoIssue")
    end
  end

  -- The instruction itself still has to be typed or pasted; put it on the
  -- clipboard so it is one paste away in the Claude terminal.
  vim.fn.setreg(
    "+",
    "Triage these TODO comments into GitHub issues. Group duplicates, "
      .. "drop anything stale or already done, and for each issue you "
      .. "create rewrite the comment in place as `KEYWORD(#N):`."
  )
  vim.notify(("Sent %d TODOs to Claude (prompt copied)"):format(#items))
end

return M
