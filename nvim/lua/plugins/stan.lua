return {
  -- Add Tree-sitter support for Stan (Syntax Highlighting)
  {
    "nvim-treesitter/nvim-treesitter",
    opts = function(_, opts)
      if type(opts.ensure_installed) == "table" then
        vim.list_extend(opts.ensure_installed, { "stan" })
      end

      -- Register the Stan parser repository manually
      local parsers = require("nvim-treesitter.parsers")
      parsers.stan = {
        install_info = {
          url = "https://github.com/WardBrian/tree-sitter-stan",
          files = { "src/parser.c" },
        },
        filetype = "stan",
      }

      -- Ensure Neovim recognizes .stan files
      vim.filetype.add({
        extension = { stan = "stan" },
      })
    end,
  },

  -- Configure the Stan Language Server
  {
    "neovim/nvim-lspconfig",
    opts = {
      servers = {
        stan_ls = {}, -- LazyVim will automatically install this via Mason
      },
    },
  },
}
