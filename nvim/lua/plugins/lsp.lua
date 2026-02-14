return {
  {
    "neovim/nvim-lspconfig",
    opts = {
      servers = {
        -- R Language Server
        r_language_server = {
          -- Install with: install.packages("languageserver")
          cmd = { "R", "--slave", "-e", "languageserver::run()" },
          filetypes = { "r", "rmd", "quarto" },
        },

        -- Julia Language Server
        julials = {
          -- Mason should handle installation
          -- Or manually: using Pkg; Pkg.add("LanguageServer")
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
    },
  },
}
