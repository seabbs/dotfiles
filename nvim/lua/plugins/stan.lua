local function register_stan()
  local parsers = require("nvim-treesitter.parsers")
  parsers.stan = {
    install_info = {
      url = "https://github.com/WardBrian/tree-sitter-stan",
      -- Repo lays the Stan grammar under grammars/stan/.
      location = "grammars/stan",
    },
    filetype = "stan",
  }
end

vim.filetype.add({ extension = { stan = "stan" } })

return {
  -- Tree-sitter support for Stan (syntax highlighting).
  {
    "nvim-treesitter/nvim-treesitter",
    opts = function(_, opts)
      if type(opts.ensure_installed) == "table" then
        vim.list_extend(opts.ensure_installed, { "stan" })
      end
      -- Initial registration so the first install pass sees stan.
      register_stan()
      -- Re-apply after every parser-table reload (the install path
      -- in v1.0+ wipes the module before reloading and fires this).
      vim.api.nvim_create_autocmd("User", {
        pattern = "TSUpdate",
        callback = register_stan,
      })
    end,
  },
  -- Stan language server (installed via Mason).
  {
    "neovim/nvim-lspconfig",
    opts = {
      servers = {
        stan_ls = {},
      },
    },
  },
}
