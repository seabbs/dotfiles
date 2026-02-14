return {
  "Vigemus/iron.nvim",
  keys = {
    -- REPL management
    {
      "<leader>rs",
      "<cmd>IronRepl<cr>",
      desc = "Toggle REPL",
    },
    {
      "<leader>rr",
      "<cmd>IronRestart<cr>",
      desc = "Restart REPL",
    },
    {
      "<leader>rf",
      function()
        require("iron.core").focus_on()
      end,
      desc = "Focus REPL",
    },
    {
      "<leader>rh",
      function()
        require("iron.core").close_repl()
      end,
      desc = "Hide REPL",
    },
    {
      "<leader>rk",
      function()
        pcall(require("iron.core").focus_on)
        vim.cmd("bd!")
      end,
      desc = "Kill REPL",
    },

    -- Language-specific REPLs
    {
      "<leader>rj",
      function()
        require("iron.core").repl_for("julia")
      end,
      desc = "Julia REPL",
    },
    {
      "<leader>rR",
      function()
        require("iron.core").repl_for("r")
      end,
      desc = "R REPL",
    },
    {
      "<leader>rp",
      function()
        require("iron.core").repl_for("python")
      end,
      desc = "Python REPL",
    },

    -- Send code (normal mode)
    {
      "<leader>sc",
      function()
        require("iron.core").send_line()
      end,
      desc = "Send line to REPL",
    },
    {
      "<leader>sf",
      function()
        require("iron.core").send_file()
      end,
      desc = "Send file to REPL",
    },
    {
      "<leader>sp",
      function()
        require("iron.core").send_paragraph()
      end,
      desc = "Send paragraph to REPL",
    },
    {
      "<leader>sF",
      function()
        require("iron.core").send_motion("af")
      end,
      desc = "Send function to REPL",
    },
    {
      "<leader>su",
      function()
        require("iron.core").send_until_cursor()
      end,
      desc = "Send until cursor to REPL",
    },

    -- Send code (visual mode)
    {
      "<leader>sc",
      function()
        require("iron.core").visual_send()
      end,
      mode = "v",
      desc = "Send selection to REPL",
    },

    -- Marks
    {
      "<leader>s<cr>",
      function()
        require("iron.core").send_mark()
      end,
      desc = "Send mark to REPL",
    },
    {
      "<leader>sm",
      function()
        require("iron.core").mark_motion("af")
      end,
      desc = "Mark function",
    },
    {
      "<leader>sd",
      function()
        require("iron.core").remove_mark()
      end,
      desc = "Remove mark",
    },
  },
  config = function()
    require("iron.core").setup({
      config = {
        scratch_repl = true,
        repl_definition = {
          r = { command = { "radian" } },
          julia = { command = { "julia" } },
          python = {
            command = { "python3" },
            format =
              require("iron.fts.common").bracketed_paste,
          },
        },
        preferred_ft = {
          rmd = "r",
          quarto = "r",
        },
        repl_open_cmd =
          require("iron.view").split.vertical.botright(80),
      },
      keymaps = {
        send_motion = false,
        visual_send = false,
        send_file = false,
        send_line = false,
        send_paragraph = false,
        send_until_cursor = false,
        send_mark = false,
        mark_motion = false,
        mark_visual = false,
        remove_mark = false,
        cr = false,
        interrupt = false,
        exit = false,
        clear = false,
      },
      highlight = { italic = true },
      ignore_blank_lines = true,
    })

    -- R: start httpgd plot server
    vim.api.nvim_create_autocmd("FileType", {
      pattern = { "r", "rmd", "quarto" },
      callback = function()
        vim.keymap.set("n", "<leader>so", function()
          require("iron.core").send(
            nil,
            "library(httpgd)\nhgd()\nhgd_browse()"
          )
        end, {
          buffer = true,
          desc = "Start httpgd server",
        })
      end,
    })

    -- Quarto/Rmd: send code blocks
    vim.api.nvim_create_autocmd("FileType", {
      pattern = { "rmd", "quarto" },
      callback = function()
        local iron_core = require("iron.core")
        local quarto = require("iron.quarto")

        vim.keymap.set("n", "<leader>sb", function()
          local code = quarto.send_code_block()
          if code ~= "" then
            iron_core.send(nil, code)
          end
        end, {
          buffer = true,
          desc = "Send code block to REPL",
        })

        vim.keymap.set("n", "<leader>sa", function()
          local code = quarto.send_all_code_blocks()
          if code ~= "" then
            iron_core.send(nil, code)
          end
        end, {
          buffer = true,
          desc = "Send all code blocks to REPL",
        })
      end,
    })
  end,
}
