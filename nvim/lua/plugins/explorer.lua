-- Make the snacks file explorer behave like a transient picker:
-- close after opening a file or losing focus, instead of sticking
-- around as a sidebar.
return {
  {
    "folke/snacks.nvim",
    opts = {
      explorer = {
        -- Don't auto-open the explorer when nvim launches on a
        -- directory (`nvim .`). Open it on demand via <leader>e.
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
