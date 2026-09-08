return {
  {
    "neovim/nvim-lspconfig",
    opts = {
      servers = {
        -- R Language Server.
        -- cmd/filetypes live in after/lsp/r_language_server.lua so they
        -- survive nvim-lspconfig's own lsp/ config in the merge order.
        r_language_server = {},

        -- Julia Language Server. julia-lsp is installed via Mason and
        -- bundles LanguageServer.jl in its own depot. Its cmd lives in
        -- after/lsp/julials.lua for the same merge-order reason.
        julials = {
          settings = {
            julia = {
              format = {
                indent = 4,
              },
              lint = {
                run = true,
              },
            },
          },
        },

        -- Python Language Server
        basedpyright = {
          -- Mason handles installation
          settings = {
            basedpyright = {
              analysis = {
                typeCheckingMode = "basic",
                autoSearchPaths = true,
                useLibraryCodeForTypes = true,
              },
            },
          },
        },
      },
      setup = {
        -- Same mason-lspconfig override problem as julials below, but
        -- with no before_init to even attempt a repair: mason's
        -- lsp/r_language_server.lua is just { cmd = { "r-languageserver" } },
        -- and that wrapper points R at mason's own package library, which
        -- is missing `collections` and segfaults on startup. Exclude it so
        -- lspconfig's default `R --no-echo -e "languageserver::run()"` runs
        -- against the system library instead.
        r_language_server = function(server, sopts)
          vim.lsp.config(server, sopts)
          vim.lsp.enable(server)
          return true
        end,

        -- mason-lspconfig's automatic_enable runs
        --   vim.lsp.config("julials", require("mason-lspconfig.lsp.julials"))
        -- which pins cmd to a bare { "julia-lsp" } on the highest
        -- precedence layer, beating opts.servers and after/lsp/ alike.
        -- It means to repair cmd in before_init, but nvim spawns the
        -- process in Client.create and only calls before_init later in
        -- Client:initialize, so the fix never lands and julia-lsp exits
        -- with "Usage: julia-lsp <julia-env-path>".
        --
        -- Returning true adds julials to mason-lspconfig's exclude list
        -- so after/lsp/julials.lua wins. LazyVim skips its own
        -- config/enable calls when a setup hook returns true, so do them
        -- here. Drop this if mason-lspconfig stops setting cmd itself.
        julials = function(server, sopts)
          vim.lsp.config(server, sopts)
          vim.lsp.enable(server)
          return true
        end,
      },
    },
  },
}
