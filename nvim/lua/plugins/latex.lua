return {
  -- render-markdown keys its LaTeX handler off the `latex` treesitter
  -- language, injected into $..$ / $$..$$ by the markdown_inline queries.
  -- Without this parser the handler never runs and math stays as source.
  {
    "nvim-treesitter/nvim-treesitter",
    opts = { ensure_installed = { "latex" } },
  },

  -- Enable LaTeX rendering in render-markdown.nvim
  -- (already installed via LazyVim markdown extra)
  {
    "MeanderingProgrammer/render-markdown.nvim",
    -- LazyVim lazy-loads this on markdown/rmd/org only, so .qmd files
    -- (filetype "quarto") never load it. lazy.nvim unions ft across specs.
    ft = { "quarto" },
    opts = {
      file_types = {
        "markdown",
        "quarto",
      },
      latex = {
        enabled = true,
        highlight = "RenderMarkdownMath",
      },
    },
  },

  -- Nabla: hover-preview LaTeX as ASCII/Unicode art
  {
    "jbyuki/nabla.nvim",
    lazy = true,
    keys = {
      {
        "<leader>mn",
        function()
          require("nabla").popup()
        end,
        desc = "LaTeX equation preview",
      },
      {
        "<leader>mN",
        function()
          require("nabla").toggle_virt()
        end,
        desc = "Toggle inline LaTeX",
      },
    },
  },
}
