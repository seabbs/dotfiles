-- Keymaps are automatically loaded on the VeryLazy event
-- Default keymaps that are always set: https://github.com/LazyVim/LazyVim/blob/main/lua/lazyvim/config/keymaps.lua
-- Add any additional keymaps here

-- Command discovery (similar to leader key experience)
vim.keymap.set("n", "<leader>:", function()
  require("fzf-lua").commands()
end, { desc = "Commands" })

vim.keymap.set("n", "<leader>;", function()
  require("fzf-lua").command_history()
end, { desc = "Command History" })

-- Molten/Quarto specific command discovery
vim.keymap.set("n", "<leader>cm", function()
  require("fzf-lua").commands({ query = "Molten" })
end, { desc = "Molten Commands" })

vim.keymap.set("n", "<leader>cq", function()
  require("fzf-lua").commands({ query = "Quarto" })
end, { desc = "Quarto Commands" })

-- Open current file in system default app (Preview for images)
vim.keymap.set("n", "<leader>fo", function()
  vim.fn.jobstart({ "open", vim.fn.expand("%:p") }, { detach = true })
end, { desc = "Open file in system app" })

-- Taskwarrior (binary is keg-only as `task`; reached via the shim)
local tw = vim.fn.expand("~/.local/share/tw-shim/task")
local tw_tui = vim.fn.expand("~/code/seabbs/dotfiles/scripts/taskwarrior-tui.sh")
-- Set TASKRC explicitly so the keymaps work even when nvim is launched
-- outside a shell that sourced taskwarrior.zsh.
local tw_env = { TASKRC = vim.fn.expand("~/.config/task/taskrc") }

-- Resolve the Obsidian vault root (where `note:` paths are relative to)
local function vault_dir()
  local ok, obsidian = pcall(require, "obsidian")
  if ok and obsidian.get_client then
    local cok, client = pcall(obsidian.get_client)
    if cok and client and client.dir then
      return tostring(client.dir)
    end
  end
  return vim.fn.expand(
    "~/Library/CloudStorage/GoogleDrive-s.e.abbott12@gmail.com/"
      .. "My Drive/cloud/apps/obsidian/notes"
  )
end

-- Path of the current buffer relative to the vault root (for the `note` UDA),
-- so it resolves back via vault_dir(); falls back to the basename.
local function note_rel_path()
  local full = vim.fn.expand("%:p")
  if full == "" then
    return nil
  end
  local root = vault_dir()
  if full:sub(1, #root + 1) == root .. "/" then
    return full:sub(#root + 2)
  end
  return vim.fn.expand("%:t")
end

-- Run `tw` and notify with its output
local function tw_run(args)
  vim.system(vim.list_extend({ tw }, args), { text = true, env = tw_env }, function(res)
    vim.schedule(function()
      vim.notify(vim.trim((res.stdout or "") .. (res.stderr or "")), vim.log.levels.INFO, {
        title = "Taskwarrior",
      })
    end)
  end)
end

-- Pick a pending task via fzf-lua and call on_pick(task). An optional filter
-- narrows the list (e.g. only tasks with a linked note).
local function pick_task(prompt, on_pick, filter)
  local res = vim.system({ tw, "status:pending", "export" }, { text = true, env = tw_env }):wait()
  local ok, tasks = pcall(vim.json.decode, res.stdout or "")
  if not ok or type(tasks) ~= "table" then
    vim.notify("Could not read tasks from Taskwarrior", vim.log.levels.ERROR)
    return
  end
  local entries, by_line = {}, {}
  for _, t in ipairs(tasks) do
    if not filter or filter(t) then
      local proj = t.project and ("[" .. t.project .. "] ") or ""
      local line = string.format("%3d  %s%s", t.id or 0, proj, t.description or "")
      entries[#entries + 1] = line
      by_line[line] = t
    end
  end
  if #entries == 0 then
    vim.notify("No matching tasks", vim.log.levels.INFO)
    return
  end
  require("fzf-lua").fzf_exec(entries, {
    prompt = prompt,
    actions = {
      ["default"] = function(selected)
        local t = selected and by_line[selected[1]]
        if t then
          on_pick(t)
        end
      end,
    },
  })
end

-- Pick a markdown note from the vault (relative path) and call cb(rel_path)
local function pick_vault_note(prompt, cb)
  local root = vault_dir()
  local rels = {}
  for _, f in ipairs(vim.fn.globpath(root, "**/*.md", false, true)) do
    if f:sub(1, #root + 1) == root .. "/" then
      rels[#rels + 1] = f:sub(#root + 2)
    end
  end
  if #rels == 0 then
    vim.notify("No notes found in vault", vim.log.levels.WARN)
    return
  end
  require("fzf-lua").fzf_exec(rels, {
    prompt = prompt,
    actions = {
      ["default"] = function(selected)
        local note = selected and selected[1]
        if note then
          cb(note)
        end
      end,
    },
  })
end

-- Open the Taskwarrior TUI in a floating terminal
vim.keymap.set("n", "<leader>nk", function()
  Snacks.terminal(tw_tui, {
    win = { style = "float", width = 0.85, height = 0.85, border = "rounded" },
  })
end, { desc = "Tasks (Taskwarrior TUI)" })

-- Quick capture: prompt -> tw add (supports attrs, e.g. project:papers due:monday)
vim.keymap.set("n", "<leader>nc", function()
  vim.ui.input({ prompt = "tw add: " }, function(input)
    if not input or input == "" then
      return
    end
    tw_run(vim.list_extend({ "add" }, vim.split(input, " ", { trimempty = true })))
  end)
end, { desc = "Tasks: capture" })

-- Capture the current line as a task (strips a leading "- [ ] " checkbox),
-- tagged +inbox and linked to the current note via the `note` UDA
vim.keymap.set("n", "<leader>nC", function()
  local line = vim.api.nvim_get_current_line()
  local desc = line:gsub("^%s*[-*]%s*%[[ xX]%]%s*", ""):gsub("^%s*[-*]%s*", "")
  desc = vim.trim(desc)
  if desc == "" then
    vim.notify("Nothing on this line to capture", vim.log.levels.WARN)
    return
  end
  local args = vim.list_extend({ "add", "+inbox" }, vim.split(desc, " ", { trimempty = true }))
  local note = note_rel_path()
  if note ~= "" then
    table.insert(args, "note:" .. note)
  end
  tw_run(args)
end, { desc = "Tasks: capture current line" })

-- Jump from a task to its linked note, opened in nvim
vim.keymap.set("n", "<leader>nj", function()
  pick_task("Task note> ", function(t)
    local path = vault_dir() .. "/" .. t.note
    if vim.fn.filereadable(path) == 0 then
      vim.notify("Note not found: " .. path, vim.log.levels.WARN)
      return
    end
    vim.cmd("edit " .. vim.fn.fnameescape(path))
  end, function(t)
    return t.note and t.note ~= ""
  end)
end, { desc = "Tasks: open linked note" })

-- Link the current note to an existing task (pick the task)
vim.keymap.set("n", "<leader>nL", function()
  local note = note_rel_path()
  if not note or note == "" then
    vim.notify("No file in this buffer to link", vim.log.levels.WARN)
    return
  end
  pick_task("Link " .. note .. " to> ", function(t)
    tw_run({ tostring(t.id), "modify", "note:" .. note })
  end)
end, { desc = "Tasks: link current note to a task" })

-- Attach a note to a task: pick the task, then pick the vault note
vim.keymap.set("n", "<leader>nA", function()
  pick_task("Attach note to task> ", function(t)
    vim.schedule(function()
      pick_vault_note("Note for task " .. (t.id or "") .. "> ", function(note)
        tw_run({ tostring(t.id), "modify", "note:" .. note })
      end)
    end)
  end)
end, { desc = "Tasks: attach a note to a task" })
