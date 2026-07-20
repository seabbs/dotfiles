-- Bridge todo-comments.nvim to GitHub issues.
--
-- LazyVim already installs todo-comments and owns the navigate/find half
-- (]t, [t, <leader>st, <leader>xt); those are left alone. Everything added
-- here lives under <leader>k, chosen because it was one of the few free
-- single-letter prefixes: <leader>t is neotest and <leader>o is octo.
return {
  "folke/todo-comments.nvim",
  keys = {
    { "<leader>k", "", desc = "+todo" },
    {
      "<leader>kn",
      function()
        require("util.todo-issue").insert("TODO")
      end,
      desc = "New TODO comment (filetype-aware)",
    },
    {
      "<leader>kN",
      function()
        require("util.todo-issue").insert_pick()
      end,
      desc = "New FIXME/HACK/... comment (pick type)",
    },
    {
      "<leader>ki",
      function()
        require("util.todo-issue").create()
      end,
      desc = "Create issue from TODO on this line",
    },
    {
      "<leader>kl",
      function()
        require("util.todo-issue").list_unlinked()
      end,
      desc = "List untracked TODOs (quickfix)",
    },
    {
      "<leader>ka",
      function()
        require("util.todo-issue").send_to_claude()
      end,
      desc = "Send untracked TODOs to Claude",
    },
  },
  opts = {
    -- Highlight `TODO(#42):` the same as a bare `TODO:` so linked comments
    -- stay visible rather than falling out of the picker.
    highlight = {
      pattern = [[.*<((KEYWORDS)%(\(.{-1,}\))?):]],
    },
    search = {
      pattern = [[\b(KEYWORDS)(\(.*\))?:]],
    },
  },
}
