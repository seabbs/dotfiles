return {
  "jpalardy/vim-slime",
  init = function()
    -- Send to tmux
    vim.g.slime_target = "tmux"

    -- Default to bottom-right pane in current window
    vim.g.slime_default_config = {
      socket_name = "default",
      target_pane = "{bottom-right}",
    }

    -- Skip the interactive prompt (use defaults above)
    vim.g.slime_dont_ask_default = 1

    -- Bracketed paste for proper multiline handling
    vim.g.slime_bracketed_paste = 1

    -- No default mappings (we define our own below)
    vim.g.slime_no_mappings = 1
  end,
  config = function()
    local function send_text(text)
      -- Use slime's internal send function
      vim.fn["slime#send"](text .. "\n")
    end

    local function send_lines(start_line, end_line)
      local lines = vim.api.nvim_buf_get_lines(
        0, start_line - 1, end_line, false
      )
      local text = table.concat(lines, "\n")
      send_text(text)
    end

    -- Send current line
    vim.keymap.set("n", "<leader>sc", function()
      local line = vim.api.nvim_get_current_line()
      send_text(line)
    end, { desc = "Send line to REPL" })

    -- Send visual selection (use slime's built-in)
    vim.keymap.set("x", "<leader>sc", "<Plug>SlimeRegionSend",
      { desc = "Send selection to REPL" })

    -- Send paragraph
    vim.keymap.set("n", "<leader>sp",
      "<Plug>SlimeParagraphSend",
      { desc = "Send paragraph to REPL" })

    -- Send file
    vim.keymap.set("n", "<leader>sf", function()
      local lines = vim.api.nvim_buf_get_lines(
        0, 0, -1, false
      )
      send_text(table.concat(lines, "\n"))
    end, { desc = "Send file to REPL" })

    -- Send up to cursor (inclusive)
    vim.keymap.set("n", "<leader>su", function()
      local cursor = vim.api.nvim_win_get_cursor(0)[1]
      send_lines(1, cursor)
    end, { desc = "Send up to cursor" })

    -- Send function (treesitter-aware)
    vim.keymap.set("n", "<leader>sF", function()
      local ts = vim.treesitter
      local node = ts.get_node()
      if not node then return end

      -- Walk up to find function node
      while node do
        local type = node:type()
        if type == "function_definition"
          or type == "function_declaration"
          or type == "method_definition" then
          break
        end
        node = node:parent()
      end

      if node then
        local sr, _, er, _ = node:range()
        send_lines(sr + 1, er + 1)
      else
        vim.notify(
          "No function found at cursor",
          vim.log.levels.WARN
        )
      end
    end, { desc = "Send function to REPL" })

    -- Reconfigure target pane
    vim.keymap.set("n", "<leader>s=",
      "<Plug>SlimeConfig",
      { desc = "Set REPL target pane" })

    -- Quarto/Rmd code blocks
    vim.api.nvim_create_autocmd("FileType", {
      pattern = { "rmd", "quarto", "markdown" },
      callback = function()
        local quarto = require("slime.quarto")

        vim.keymap.set("n", "<leader>sb", function()
          local code = quarto.get_code_block()
          if code ~= "" then
            send_text(code)
          end
        end, {
          buffer = true,
          desc = "Send code block to REPL",
        })

        vim.keymap.set("n", "<leader>sa", function()
          local code = quarto.get_all_code_blocks()
          if code ~= "" then
            send_text(code)
          end
        end, {
          buffer = true,
          desc = "Send all code blocks to REPL",
        })

        vim.keymap.set("n", "<leader>sU", function()
          local code = quarto.get_code_blocks_to_cursor()
          if code ~= "" then
            send_text(code)
          end
        end, {
          buffer = true,
          desc = "Send code blocks up to cursor",
        })
      end,
    })

    -- Julia/Literate.jl code blocks
    vim.api.nvim_create_autocmd("FileType", {
      pattern = { "julia" },
      callback = function()
        local literate = require("slime.literate")

        vim.keymap.set("n", "<leader>sb", function()
          local code = literate.get_code_block()
          if code ~= "" then
            send_text(code)
          end
        end, {
          buffer = true,
          desc = "Send code block to REPL",
        })

        vim.keymap.set("n", "<leader>sa", function()
          local code = literate.get_all_code_blocks()
          if code ~= "" then
            send_text(code)
          end
        end, {
          buffer = true,
          desc = "Send all code blocks to REPL",
        })

        vim.keymap.set("n", "<leader>sU", function()
          local code =
            literate.get_code_blocks_to_cursor()
          if code ~= "" then
            send_text(code)
          end
        end, {
          buffer = true,
          desc = "Send code blocks up to cursor",
        })
      end,
    })

    -- R: start httpgd plot server
    vim.api.nvim_create_autocmd("FileType", {
      pattern = { "r", "rmd", "quarto" },
      callback = function()
        vim.keymap.set("n", "<leader>so", function()
          send_text(
            "library(httpgd)\nhgd()\nhgd_browse()"
          )
        end, {
          buffer = true,
          desc = "Start httpgd server",
        })
      end,
    })
  end,
}
