return {
  {
    "catppuccin/nvim",
    name = "catppuccin",
    priority = 1000,
    opts = {
      flavour = "macchiato",
      integrations = {
        cmp = true,
        gitsigns = true,
        harpoon = true,
        illuminate = true,
        mason = true,
        native_lsp = { enabled = true },
        neotest = true,
        noice = true,
        notify = true,
        snacks = { enabled = true },
        telescope = { enabled = true },
        treesitter = true,
        which_key = true,
      },
    },
  },
  {
    "LazyVim/LazyVim",
    opts = { colorscheme = "catppuccin-macchiato" },
  },
}
