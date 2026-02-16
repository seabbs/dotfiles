return {
  "nvim-telescope/telescope-frecency.nvim",
  dependencies = { "nvim-telescope/telescope.nvim" },
  config = function()
    require("telescope").load_extension("frecency")
  end,
  keys = {
    {
      "<leader>fF",
      "<cmd>Telescope frecency<cr>",
      desc = "Frequent files",
    },
  },
}
