return {
  "mrjones2014/legendary.nvim",
  priority = 10000,
  lazy = false,
  dependencies = { "folke/which-key.nvim" },
  opts = {
    extensions = {
      which_key = { auto_register = true },
      lazy_nvim = true,
    },
  },
  keys = {
    {
      "<leader>?",
      "<cmd>Legendary<cr>",
      desc = "Keybinding cheatsheet",
    },
  },
}
