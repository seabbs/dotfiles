-- Claude Code through sidekick.nvim. Claude runs in a tmux split, one
-- session per project directory, so it outlives nvim. <C-.> focuses it,
-- and the usual pane keys move back.
-- Next edit suggestions stay off: suggestions are opt-in here.
local function cli()
  return require("sidekick.cli")
end

return {
  "folke/sidekick.nvim",
  opts = {
    nes = { enabled = false },
    cli = {
      mux = { enabled = true, backend = "tmux", create = "split" },
    },
  },
  keys = {
    {
      "<c-.>",
      function()
        cli().focus({ name = "claude" })
      end,
      mode = { "n", "x", "i" },
      desc = "Focus Claude",
    },
    {
      "<leader>aa",
      function()
        cli().toggle({ name = "claude", focus = true })
      end,
      desc = "Toggle Claude",
    },
    {
      "<leader>al",
      function()
        cli().send({ name = "claude", msg = "{line}" })
      end,
      desc = "Send line",
    },
    {
      "<leader>ax",
      function()
        cli().send({ name = "claude", msg = "{diagnostics}" })
      end,
      desc = "Send diagnostics",
    },
    {
      "<leader>aq",
      function()
        cli().send({ name = "claude", msg = "Fix these failing tests or errors:\n{quickfix}" })
      end,
      desc = "Ask Claude to fix the quickfix list",
    },
  },
}
