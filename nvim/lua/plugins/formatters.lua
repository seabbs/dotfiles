return {
  {
    "stevearc/conform.nvim",
    optional = true,
    opts = {
      formatters_by_ft = {
        r = { "air" },
        rmd = { "air" },
        quarto = { "air" },
        -- Runic is the Julia formatter used across EpiAware
        -- (replacing JuliaFormatter). Installed as a standalone
        -- app by julia/setup.sh -> ~/.julia/bin/runic. conform
        -- ships a built-in runic formatter (PR #657), so no
        -- custom formatter block is needed. See issue #76.
        julia = { "runic" },
      },
    },
  },
}
