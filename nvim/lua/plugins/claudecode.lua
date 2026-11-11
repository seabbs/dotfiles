return {
  "coder/claudecode.nvim",
  dependencies = { "folke/snacks.nvim" },
  config = true,
  keys = {
    { "<leader>a", nil, desc = "AI/Claude Code" },
    { "<leader>ac", "<cmd>ClaudeCode<cr>", desc = "Toggle Claude" },
    { "<leader>af", "<cmd>ClaudeCodeFocus<cr>", desc = "Focus Claude" },
    { "<leader>ar", "<cmd>ClaudeCode --resume<cr>", desc = "Resume Claude" },
    { "<leader>aC", "<cmd>ClaudeCode --continue<cr>", desc = "Continue Claude" },
    { "<leader>am", "<cmd>ClaudeCodeSelectModel<cr>", desc = "Select Claude model" },
    { "<leader>ab", "<cmd>ClaudeCodeAdd %<cr>", desc = "Add current buffer" },
    -- Move between code and Claude: <C-,> focuses Claude (opening it if
    -- needed); in the Claude pane it jumps back to the code, leaving
    -- Claude open.
    { "<C-,>", "<cmd>ClaudeCodeFocus<cr>", desc = "Focus Claude" },
    { "<C-,>", "<C-\\><C-n><C-w>p", mode = "t", desc = "Back to code" },
    { "<leader>al", "<cmd>.ClaudeCodeSend<cr>", desc = "Send line to Claude" },
    {
      "<leader>aP",
      "vip<cmd>ClaudeCodeSend<cr>",
      remap = true,
      desc = "Send paragraph to Claude",
    },
    { "<leader>as", "<cmd>ClaudeCodeSend<cr>", mode = "v", desc = "Send to Claude" },
    {
      "<leader>as",
      "<cmd>ClaudeCodeTreeAdd<cr>",
      desc = "Add file",
      ft = { "NvimTree", "neo-tree", "oil", "minifiles" },
    },
    -- Diff management
    { "<leader>aa", "<cmd>ClaudeCodeDiffAccept<cr>", desc = "Accept diff" },
    { "<leader>ad", "<cmd>ClaudeCodeDiffDeny<cr>", desc = "Deny diff" },
  },
}