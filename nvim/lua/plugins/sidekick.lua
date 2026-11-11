-- Claude Code through sidekick.nvim. Sessions run in tmux (one per
-- project directory), so they outlive nvim and survive restarts.
-- <C-.> moves between code and Claude, leaving Claude open.
-- Next edit suggestions stay off: suggestions are opt-in here.
local function cli()
  return require("sidekick.cli")
end

return {
  "folke/sidekick.nvim",
  opts = {
    nes = { enabled = false },
    cli = {
      mux = { enabled = true, backend = "tmux", create = "terminal" },
      win = {
        keys = {
          hide_ctrl_dot = {
            "<c-.>",
            "blur",
            mode = "nt",
            desc = "back to the code, leaving Claude open",
          },
        },
      },
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
        cli().send({ name = "claude", msg = "{quickfix}" })
      end,
      desc = "Send quickfix list",
    },
  },
}
