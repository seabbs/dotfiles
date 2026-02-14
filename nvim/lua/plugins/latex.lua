return {
  -- Enable LaTeX rendering in render-markdown.nvim
  -- (already installed via LazyVim markdown extra)
  {
    "MeanderingProgrammer/render-markdown.nvim",
    opts = {
      file_types = {
        "markdown",
        "quarto",
        "qmd",
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
