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
        -- No `keymap` option here: quarto-nvim has never had one, so a
        -- table like { hover = "K", definition = "gd" } is silently
        -- ignored. K/gd/gr come from LazyVim's LSP keymaps and reach the
        -- chunk's language server through the otter-ls client attached to
        -- the .qmd buffer.
      })
      
      -- Quarto-specific keymaps
      local keymap = vim.keymap.set
      local runner = require("quarto.runner")
      
      -- Code execution, under <localleader>m alongside molten's own
      -- kernel maps. R.nvim binds buffer-local \rc \ra \rl \rr and \qp
      -- from its quarto ftplugin, and buffer-local always beats these
      -- global maps, so the old \r* keys silently ran R.nvim instead.
      -- \m* is safe: R.nvim only binds bare \m, and nvim prefers the
      -- longer match when a global \m<x> exists.
      keymap("n", "<localleader>mc", runner.run_cell, { desc = "Run cell" })
      keymap("n", "<localleader>ma", runner.run_above, { desc = "Run cell and above" })
      keymap("n", "<localleader>mA", runner.run_all, { desc = "Run all cells" })
      keymap("n", "<localleader>ml", runner.run_line, { desc = "Run line" })
      keymap("v", "<localleader>mv", runner.run_range, { desc = "Run visual range" })
      
      -- Navigation
      keymap("n", "]c", function() require("quarto.runner").run_cell() end, { desc = "Run cell and move to next" })
      keymap("n", "[c", function()
        require("quarto.runner").run_cell()
        vim.api.nvim_feedkeys("k", "n", false)
      end, { desc = "Run cell and move to previous" })
      
      -- Quarto preview
      -- \qp is R.nvim's quarto::quarto_preview() (buffer-local, wins).
      keymap("n", "<localleader>mp", ":QuartoPreview<CR>", { desc = "Quarto preview" })
      keymap("n", "<localleader>mP", ":QuartoClosePreview<CR>", { desc = "Close Quarto preview" })
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