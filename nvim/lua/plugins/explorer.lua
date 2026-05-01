-- Make the snacks file explorer behave like a transient picker:
-- close after opening a file or losing focus, instead of sticking
-- around as a sidebar.
return {
  {
    "folke/snacks.nvim",
    opts = {
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
