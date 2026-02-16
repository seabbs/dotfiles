return {
  "mbbill/undotree",
  keys = {
    {
      "<leader>uu",
      "<cmd>UndotreeToggle<cr>",
      desc = "Toggle undo tree",
    },
  },
  config = function()
    vim.g.undotree_SetFocusWhenToggle = 1
    vim.g.undotree_WindowLayout = 2
  end,
}
