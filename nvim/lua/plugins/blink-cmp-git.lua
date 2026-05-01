return {
  "Kaiser-Yang/blink-cmp-git",
  dependencies = { "saghen/blink.cmp" },
  -- Loaded as a blink.cmp source; the upstream module has no setup().
  config = function() end,
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
