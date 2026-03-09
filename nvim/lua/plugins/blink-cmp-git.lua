return {
  "Kaiser-Yang/blink-cmp-git",
  dependencies = { "saghen/blink.cmp" },
  opts = {},
  specs = {
    {
      "saghen/blink.cmp",
      opts = {
        sources = {
          default = { "git" },
          providers = {
            git = {
              module = "blink-cmp-git",
              name = "Git",
              enabled = function()
                return vim.tbl_contains(
                  { "octo", "gitcommit", "markdown" },
                  vim.bo.filetype
                )
              end,
            },
          },
        },
      },
    },
  },
}
