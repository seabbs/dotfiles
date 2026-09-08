return {
  {
    "benlubas/molten-nvim",
    -- Using latest version for best compatibility
    dependencies = { "3rd/image.nvim" },
    build = ":UpdateRemotePlugins",
    -- load for all data science filetypes. `qmd` is not a real filetype
    -- (.qmd opens as `quarto`) but is harmless to list.
    ft = { "julia", "r", "python", "quarto", "qmd", "markdown" },
    -- No `cmd` trigger. molten is a remote plugin, so its commands come
    -- from the rplugin manifest and already exist at startup. lazy.nvim
    -- creates its own stubs for anything in `cmd` and deletes them when
    -- the plugin loads, expecting the plugin to redefine them -- which
    -- deleted the manifest's real :MoltenInit and left no way to start a
    -- kernel from inside a .qmd.
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
      -- molten has no :MoltenEvaluateCell -- it has no notion of a cell,
      -- the boundaries come from the plugin above it. In a quarto buffer
      -- ask quarto's runner (same thing <localleader>rc does); elsewhere
      -- fall back to re-running the cell the cursor sits in.
      keymap("n", "<localleader>ec", function()
        if vim.bo.filetype == "quarto" and pcall(require, "quarto.runner") then
          require("quarto.runner").run_cell()
        else
          vim.cmd("MoltenReevaluateCell")
        end
      end, { desc = "Evaluate cell" })
      keymap("n", "<localleader>rr", ":MoltenReevaluateCell<CR>", { desc = "Re-evaluate cell" })
      
      -- Molten management
      keymap("n", "<localleader>mr", ":MoltenRestart<CR>", { desc = "Restart kernel" })
      -- <localleader>mi is MoltenInit above; don't shadow it.
      keymap("n", "<localleader>mI", ":MoltenInfo<CR>", { desc = "Molten info" })
      keymap("n", "<localleader>md", ":MoltenDelete<CR>", { desc = "Delete kernel" })
      
      -- Language-specific shortcuts
      -- Jupyter registers Julia as julia-<major>.<minor>, never bare
      -- "julia", so pick the newest installed kernel at call time.
      keymap("n", "<localleader>jj", function()
        local kernels = vim.fn.globpath(
          vim.fn.expand("~/Library/Jupyter/kernels"), "julia-*", false, true
        )
        if #kernels == 0 then
          vim.notify("No Julia jupyter kernel found", vim.log.levels.WARN)
          return
        end
        table.sort(kernels)
        vim.cmd("MoltenInit " .. vim.fn.fnamemodify(kernels[#kernels], ":t"))
      end, { desc = "Start Julia" })
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
      max_width_window_percentage = 80,
      max_height_window_percentage = 80,
      window_overlap_clear_enabled = true,
      window_overlap_clear_ft_ignore = { "cmp_menu", "cmp_docs", "" },
      editor_only_render_when_focused = true,
      tmux_show_only_in_active_window = true,
      hijack_file_patterns = { "*.png", "*.jpg", "*.jpeg", "*.gif", "*.webp", "*.avif" },
    },
  },
}