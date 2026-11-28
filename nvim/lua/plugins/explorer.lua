-- Make the snacks file explorer behave like a transient picker:
-- close after opening a file or losing focus, instead of sticking
-- around as a sidebar.
return {
  {
    "folke/snacks.nvim",
    opts = {
      explorer = {
        -- Don't let the explorer claim a directory argument. Open it
        -- on demand via <leader>e instead.
        --
        -- With this off, a directory handed to nvim falls to netrw, so
        -- the session layouts pass no argument at all and open on the
        -- dashboard. Turning this back on would change what `nvim .`
        -- does, but the layouts would still not be doing that.
        replace_netrw = false,
      },
      picker = {
        sources = {
          explorer = {
            auto_close = true,
            jump = { close = true },
          },
        },
      },
    },
  },
}
