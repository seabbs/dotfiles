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
    local args = vim.list_extend({ tw, "add" }, vim.split(input, " ", { trimempty = true }))
    vim.system(args, { text = true }, function(res)
      vim.schedule(function()
        vim.notify(vim.trim((res.stdout or "") .. (res.stderr or "")), vim.log.levels.INFO, {
          title = "Taskwarrior",
        })
      end)
    end)
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
  local note = vim.fn.expand("%:t")
  local args = vim.list_extend({ tw, "add", "+inbox" }, vim.split(desc, " ", { trimempty = true }))
  if note ~= "" then
    table.insert(args, "note:" .. note)
  end
  vim.system(args, { text = true }, function(res)
    vim.schedule(function()
      vim.notify(vim.trim((res.stdout or "") .. (res.stderr or "")), vim.log.levels.INFO, {
        title = "Taskwarrior",
      })
    end)
  end)
end, { desc = "Tasks: capture current line" })
