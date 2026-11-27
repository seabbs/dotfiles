-- Link the current Obsidian note from today's daily note, creating the
-- daily note from its template if needed. Adds `- [[note]]` once.
return function()
  local Note = require("obsidian.note")
  local daily = require("obsidian.daily")
  local function say(msg, level)
    vim.notify(msg, level or vim.log.levels.INFO, { title = "Obsidian" })
  end

  local cur = vim.api.nvim_buf_get_name(0)
  local vault = vim.fs.normalize(tostring(Obsidian.dir))
  cur = vim.fs.normalize(cur)
  if cur == "" or not vim.startswith(cur, vault .. "/") then
    return say("Not a note in the vault", vim.log.levels.WARN)
  end

  local path = vim.fs.normalize(tostring(daily.daily_note_path()))
  if cur == path then
    return say("This is today's daily note")
  end
  if vim.bo.modified then
    vim.cmd("silent write")
  end
  if vim.fn.filereadable(path) == 0 then
    daily.today():write()
  end

  local note = Note.from_file(cur)
  local link = note:format_link()
  local target = "[[" .. note.id
  -- Edit through a buffer, so an open daily note is not changed behind
  -- its back and a file with no final newline is handled.
  local was_loaded = vim.fn.bufloaded(path) == 1
  local buf = vim.fn.bufadd(path)
  vim.fn.bufload(buf)
  for _, line in ipairs(vim.api.nvim_buf_get_lines(buf, 0, -1, false)) do
    if line:find(target, 1, true) then
      return say("Already in today's daily note")
    end
  end
  vim.api.nvim_buf_set_lines(buf, -1, -1, false, { "- " .. link })
  vim.api.nvim_buf_call(buf, function()
    vim.cmd("silent write")
  end)
  if not was_loaded then
    vim.api.nvim_buf_delete(buf, {})
  end
  say("Linked from " .. vim.fs.basename(path))
end
