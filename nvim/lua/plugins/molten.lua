return {
  {
    "benlubas/molten-nvim",
    -- Using latest version for best compatibility
    dependencies = { "3rd/image.nvim" },
    build = ":UpdateRemotePlugins",
    ft = { "julia", "r", "python", "quarto", "qmd", "markdown" }, -- load for all data science filetypes
    cmd = { "MoltenInit", "MoltenEvaluateOperator", "MoltenEvaluateLine", "MoltenEvaluateVisual" }, -- also load on command
    init = function()
      -- molten configuration
      vim.g.molten_output_win_max_height = 20
      vim.g.molten_auto_open_output = true
      vim.g.molten_wrap_output = true
      vim.g.molten_virt_text_output = true
      vim.g.molten_image_provider = "image.nvim"
    end,
    config = function()
      -- Keymaps for molten
      local keymap = vim.keymap.set
      
      -- Core molten commands
      keymap("n", "<localleader>mi", ":MoltenInit<CR>", { desc = "Init Molten" })
      keymap("n", "<localleader>e", ":MoltenEvaluateOperator<CR>", { desc = "Evaluate operator" })
      keymap("n", "<localleader>el", ":MoltenEvaluateLine<CR>", { desc = "Evaluate line" })
      keymap("v", "<localleader>e", ":<C-u>MoltenEvaluateVisual<CR>gv", { desc = "Evaluate visual" })
      keymap("n", "<localleader>ec", ":MoltenEvaluateCell<CR>", { desc = "Evaluate cell" })
      keymap("n", "<localleader>rr", ":MoltenReevaluateCell<CR>", { desc = "Re-evaluate cell" })
      
      -- Molten management
      keymap("n", "<localleader>mr", ":MoltenRestart<CR>", { desc = "Restart kernel" })
      keymap("n", "<localleader>mi", ":MoltenInfo<CR>", { desc = "Molten info" })
      keymap("n", "<localleader>md", ":MoltenDelete<CR>", { desc = "Delete kernel" })
      
      -- Language-specific shortcuts
      keymap("n", "<localleader>jj", ":MoltenInit julia<CR>", { desc = "Start Julia" })
      keymap("n", "<localleader>jr", ":MoltenInit ir<CR>", { desc = "Start R" })
      keymap("n", "<localleader>jp", ":MoltenInit python3<CR>", { desc = "Start Python" })
      
      -- Project activation helpers for Julia
      keymap("n", "<localleader>ja", function()
        vim.api.nvim_put({'using Pkg; Pkg.activate(".")'}, 'l', false, true)
        vim.cmd('MoltenEvaluateLine')
        vim.api.nvim_input('dd') -- Remove the line after evaluation
      end, { desc = "Activate Julia project" })
      
      keymap("n", "<localleader>jd", function()
        vim.api.nvim_put({'using Pkg; Pkg.activate("docs")'}, 'l', false, true)
        vim.cmd('MoltenEvaluateLine') 
        vim.api.nvim_input('dd')
      end, { desc = "Activate Julia docs env" })
    end,
  },
  {
    "3rd/image.nvim",
    event = "VeryLazy", -- Load only when needed
    cond = function()
      -- Only load if we have a supported terminal
      return vim.env.TERM_PROGRAM or vim.env.KITTY_WINDOW_ID
    end,
    opts = {
      backend = "kitty", -- or "ueberzug" if you use a different terminal
      integrations = {
        markdown = {
          enabled = true,
          clear_in_insert_mode = false,
          download_remote_images = true,
          only_render_image_at_cursor = false,
          filetypes = { "markdown", "vimwiki", "quarto", "qmd" },
        },
        neorg = {
          enabled = true,
          filetypes = { "norg" },
        },
        html = {
          enabled = false,
        },
        css = {
          enabled = false,
        },
      },
      max_width = nil,
      max_height = nil,
      max_width_window_percentage = nil,
      max_height_window_percentage = 50,
      window_overlap_clear_enabled = false,
      window_overlap_clear_ft_ignore = { "cmp_menu", "cmp_docs", "" },
      editor_only_render_when_focused = false,
      tmux_show_only_in_active_window = false,
      hijack_file_patterns = { "*.png", "*.jpg", "*.jpeg", "*.gif", "*.webp", "*.avif" },
    },
  },
}