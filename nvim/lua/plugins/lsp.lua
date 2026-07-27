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
          -- julia-lsp is installed via Mason; its wrapper bundles
          -- LanguageServer.jl in its own depot, so nothing extra to install.
          -- The wrapper needs the project's env path as a positional arg.
          -- mason-lspconfig appends it via before_init, but under nvim 0.11+
          -- that hook fires after the process spawns, so it exits 1. Skip
          -- mason auto-enable and pass the env path ourselves.
          mason = false,
          cmd = function(dispatchers)
            -- Fall back to the newest default env rather than a
            -- hardcoded version, which goes stale on each upgrade.
            -- glob() expands ~ itself; wrapping it in expand() first
            -- collapses the matches to one newline-joined string that
            -- then globs to nothing.
            local envs = vim.fn.glob("~/.julia/environments/v*", false, true)
            -- Sort on the numeric version, not the string: v1.9 sorts
            -- after v1.10 lexicographically.
            local function version(path)
              local major, minor = path:match("v(%d+)%.(%d+)$")
              return (tonumber(major) or 0) * 1000 + (tonumber(minor) or 0)
            end
            table.sort(envs, function(a, b)
              return version(a) < version(b)
            end)
            local root = vim.fs.root(0, { "Project.toml", "JuliaProject.toml" })
              or envs[#envs]
            return vim.lsp.rpc.start({ "julia-lsp", root }, dispatchers)
          end,
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
