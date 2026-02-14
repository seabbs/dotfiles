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
