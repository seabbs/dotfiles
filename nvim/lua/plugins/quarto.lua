return {
  {
    "quarto-dev/quarto-nvim",
    dependencies = {
      "jmbuhr/otter.nvim",
      "nvim-treesitter/nvim-treesitter",
    },
    ft = { "quarto", "qmd" },
    config = function()
      require("quarto").setup({
        lspFeatures = {
          enabled = true,
          chunks = "curly",
          languages = { "python", "r", "julia" },
          diagnostics = {
            enabled = true,
            triggers = { "BufWritePost" },
          },
          completion = {
            enabled = true,
          },
        },
        codeRunner = {
          enabled = true,
          default_method = "molten",
          ft_runners = {
            python = "molten",
            r = "molten", 
            julia = "molten",
          },
        },
        keymap = {
          hover = "K",
          definition = "gd",
          references = "gr",
        },
      })
      
      -- Quarto-specific keymaps
      local keymap = vim.keymap.set
      local runner = require("quarto.runner")
      
      -- Code execution
      keymap("n", "<localleader>rc", runner.run_cell, { desc = "Run cell" })
      keymap("n", "<localleader>ra", runner.run_above, { desc = "Run cell and above" })
      keymap("n", "<localleader>rA", runner.run_all, { desc = "Run all cells" })
      keymap("n", "<localleader>rl", runner.run_line, { desc = "Run line" })
      keymap("v", "<localleader>r", runner.run_range, { desc = "Run visual range" })
      
      -- Navigation
      keymap("n", "]c", function() require("quarto.runner").run_cell() end, { desc = "Run cell and move to next" })
      keymap("n", "[c", function()
        require("quarto.runner").run_cell()
        vim.api.nvim_feedkeys("k", "n", false)
      end, { desc = "Run cell and move to previous" })
      
      -- Quarto preview
      keymap("n", "<localleader>qp", ":QuartoPreview<CR>", { desc = "Quarto preview" })
      keymap("n", "<localleader>qq", ":QuartoClosePreview<CR>", { desc = "Close Quarto preview" })
    end,
  },
  {
    "jmbuhr/otter.nvim",
    dependencies = {
      "nvim-treesitter/nvim-treesitter",
    },
    opts = {
      lsp = {
        hover = {
          border = "rounded",
        },
      },
      buffers = {
        set_filetype = true,
        write_to_disk = false,
      },
      strip_wrapping_quote_characters = { "'", '"', "`" },
      handle_leading_whitespace = true,
    },
  },
}