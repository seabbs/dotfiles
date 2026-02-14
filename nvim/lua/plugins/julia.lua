return {
  -- Julia debug adapter
  {
    "kdheepak/nvim-dap-julia",
    dependencies = {
      "mfussenegger/nvim-dap",
      "rcarriga/nvim-dap-ui",
    },
    ft = "julia",
    config = function()
      require("nvim-dap-julia").setup()
    end,
  },

  -- Julia keybinding group
  {
    "folke/which-key.nvim",
    optional = true,
    opts = {
      spec = {
        { "<leader>cj", group = "julia", icon = "" },
      },
    },
  },

  -- Julia REPL helpers (iron.nvim integration)
  {
    "nvim-lua/plenary.nvim",
    config = function()
      vim.api.nvim_create_autocmd("FileType", {
        pattern = "julia",
        callback = function()
          local map = vim.keymap.set
          local opts = { buffer = true }

          map("n", "<leader>cji", function()
            vim.cmd("split | terminal julia --project")
          end, vim.tbl_extend(
            "force",
            opts,
            { desc = "Open Julia REPL" }
          ))

          map("n", "<leader>cjs", function()
            local ok, iron = pcall(require, "iron.core")
            if ok then
              iron.send(nil, "using Pkg; Pkg.test()")
            else
              vim.notify(
                "iron.nvim not available",
                vim.log.levels.WARN
              )
            end
          end, vim.tbl_extend(
            "force",
            opts,
            { desc = "Send Pkg.test() to REPL" }
          ))
        end,
      })
    end,
  },
}
