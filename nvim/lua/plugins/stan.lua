return {
  -- Add Tree-sitter support for Stan (Syntax Highlighting)
  {
    "nvim-treesitter/nvim-treesitter",
    opts = function(_, opts)
      if type(opts.ensure_installed) == "table" then
        vim.list_extend(opts.ensure_installed, { "stan" })
      end
    end,
  },

  -- Configure the Stan Language Server
  {
    "neovim/nvim-lspconfig",
    opts = {
      servers = {
        stan_ls = {}, -- This configures the Stan Language Server
      },
    },
  },
  
  -- Add Mason integration to auto-install the Stan Language Server
  {
    "williamboman/mason.nvim",
    opts = function(_, opts)
      if type(opts.ensure_installed) == "table" then
        vim.list_extend(opts.ensure_installed, { "stan-language-server" })
      end
    end,
  },
}
