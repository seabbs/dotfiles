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

    -- Send line(s): supports count, e.g. 5<leader>rc
    vim.keymap.set("n", "<leader>rc", function()
      local cursor = vim.api.nvim_win_get_cursor(0)[1]
      local count = vim.v.count1
      local lines = vim.api.nvim_buf_get_lines(
        0, cursor - 1, cursor - 1 + count, false
      )
      send_text(table.concat(lines, "\n"))
    end, { desc = "Send line(s) to REPL" })

    -- Send line(s) and advance
    vim.keymap.set("n", "<leader>rC", function()
      local cursor = vim.api.nvim_win_get_cursor(0)[1]
      local count = vim.v.count1
      local lines = vim.api.nvim_buf_get_lines(
        0, cursor - 1, cursor - 1 + count, false
      )
      send_text(table.concat(lines, "\n"))
      local total = vim.api.nvim_buf_line_count(0)
      local target = math.min(cursor + count, total)
      vim.api.nvim_win_set_cursor(0, { target, 0 })
    end, { desc = "Send line(s) + advance" })

    -- Send visual selection (use slime's built-in)
    vim.keymap.set("x", "<leader>rc", "<Plug>SlimeRegionSend",
      { desc = "Send selection to REPL" })

    -- Send paragraph
    vim.keymap.set("n", "<leader>rp",
      "<Plug>SlimeParagraphSend",
      { desc = "Send paragraph to REPL" })

    -- Send paragraph and advance
    vim.keymap.set("n", "<leader>rP", function()
      local cursor = vim.api.nvim_win_get_cursor(0)[1]
      local total = vim.api.nvim_buf_line_count(0)
      local lines = vim.api.nvim_buf_get_lines(
        0, 0, -1, false
      )
      -- Skip if cursor is on a blank line
      if lines[cursor] == "" then
        vim.notify(
          "No paragraph at cursor",
          vim.log.levels.INFO
        )
        return
      end
      -- Find start of current paragraph
      local ps = cursor
      while ps > 1 and lines[ps - 1] ~= "" do
        ps = ps - 1
      end
      -- Find end of current paragraph
      local pe = cursor
      while pe < total and lines[pe + 1] ~= "" do
        pe = pe + 1
      end
      -- Send the paragraph
      send_lines(ps, pe)
      -- Advance past blank lines to next paragraph
      local i = pe + 1
      while i <= total and lines[i] == "" do
        i = i + 1
      end
      if i <= total then
        vim.api.nvim_win_set_cursor(0, { i, 0 })
      end
    end, { desc = "Send paragraph + advance" })

    -- Send file
    vim.keymap.set("n", "<leader>rf", function()
      local lines = vim.api.nvim_buf_get_lines(
        0, 0, -1, false
      )
      send_text(table.concat(lines, "\n"))
    end, { desc = "Send file to REPL" })

    -- Send up to cursor (inclusive)
    vim.keymap.set("n", "<leader>ru", function()
      local cursor = vim.api.nvim_win_get_cursor(0)[1]
      send_lines(1, cursor)
    end, { desc = "Send up to cursor" })

    -- Find top-level treesitter statement at cursor
    local function find_statement()
      local ts = vim.treesitter
      local node = ts.get_node()
      if not node then return nil end
      local root_types = {
        program = true,
        chunk = true,
        source_file = true,
        function_body = true,
        brace_list = true,  -- R
        block = true,       -- Julia/Python
      }
      -- Walk up to the nearest node whose parent is
      -- a root or function body container
      while node:parent() do
        local parent = node:parent()
        if root_types[parent:type()] then
          break
        end
        node = parent
      end
      return node
    end

    -- Send statement (treesitter-aware)
    vim.keymap.set("n", "<leader>rs", function()
      local node = find_statement()
      if node then
        local sr, _, er, _ = node:range()
        send_lines(sr + 1, er + 1)
      else
        vim.notify(
          "No statement found at cursor",
          vim.log.levels.WARN
        )
      end
    end, { desc = "Send statement to REPL" })

    -- Send statement and advance
    vim.keymap.set("n", "<leader>rS", function()
      local node = find_statement()
      if node then
        local sr, _, er, _ = node:range()
        send_lines(sr + 1, er + 1)
        local total = vim.api.nvim_buf_line_count(0)
        local target = math.min(er + 2, total)
        vim.api.nvim_win_set_cursor(0, { target, 0 })
      else
        vim.notify(
          "No statement found at cursor",
          vim.log.levels.WARN
        )
      end
    end, { desc = "Send statement + advance" })

    -- Send function (treesitter-aware)
    vim.keymap.set("n", "<leader>rF", function()
      local ts = vim.treesitter
      local node = ts.get_node()
      if not node then return end

      -- Walk up to find function/struct/macro node
      while node do
        local type = node:type()
        if type == "function_definition"
          or type == "function_declaration"
          or type == "method_definition"
          or type == "struct_definition"
          or type == "module_definition"
          or type == "macrocall_expression" then
          break
        end
        node = node:parent()
      end

      if node then
        local sr, _, er, _ = node:range()
        send_lines(sr + 1, er + 1)
      else
        vim.notify(
          "No definition found at cursor",
          vim.log.levels.WARN
        )
      end
    end, { desc = "Send definition to REPL" })

    -- Reconfigure target pane
    vim.keymap.set("n", "<leader>r=",
      "<Plug>SlimeConfig",
      { desc = "Set REPL target pane" })

    -- Quarto/Rmd code blocks
    vim.api.nvim_create_autocmd("FileType", {
      pattern = { "rmd", "quarto", "markdown" },
      callback = function()
        local quarto = require("slime.quarto")

        vim.keymap.set("n", "<leader>rb", function()
          local code = quarto.get_code_block()
          if code ~= "" then
            send_text(code)
          end
        end, {
          buffer = true,
          desc = "Send code block to REPL",
        })

        vim.keymap.set("n", "<leader>rB", function()
          local code = quarto.get_code_block()
          if code ~= "" then
            send_text(code)
            quarto.next_block()
          end
        end, {
          buffer = true,
          desc = "Send code block + advance",
        })

        vim.keymap.set("n", "<leader>ra", function()
          local code = quarto.get_all_code_blocks()
          if code ~= "" then
            send_text(code)
          end
        end, {
          buffer = true,
          desc = "Send all code blocks to REPL",
        })

        vim.keymap.set("n", "<leader>rU", function()
          local code = quarto.get_code_blocks_to_cursor()
          if code ~= "" then
            send_text(code)
          end
        end, {
          buffer = true,
          desc = "Send code blocks up to cursor",
        })

        vim.keymap.set("n", "<leader>rj", function()
          quarto.next_block()
        end, {
          buffer = true,
          desc = "Next code block",
        })

        vim.keymap.set("n", "<leader>rk", function()
          quarto.prev_block()
        end, {
          buffer = true,
          desc = "Previous code block",
        })
      end,
    })

    -- Julia/Literate.jl code blocks
    vim.api.nvim_create_autocmd("FileType", {
      pattern = { "julia" },
      callback = function()
        local literate = require("slime.literate")

        vim.keymap.set("n", "<leader>rb", function()
          local code = literate.get_code_block()
          if code ~= "" then
            send_text(code)
          end
        end, {
          buffer = true,
          desc = "Send code block to REPL",
        })

        vim.keymap.set("n", "<leader>rB", function()
          local code = literate.get_code_block()
          if code ~= "" then
            send_text(code)
            literate.next_block()
          end
        end, {
          buffer = true,
          desc = "Send code block + advance",
        })

        vim.keymap.set("n", "<leader>ra", function()
          local code = literate.get_all_code_blocks()
          if code ~= "" then
            send_text(code)
          end
        end, {
          buffer = true,
          desc = "Send all code blocks to REPL",
        })

        vim.keymap.set("n", "<leader>rU", function()
          local code =
            literate.get_code_blocks_to_cursor()
          if code ~= "" then
            send_text(code)
          end
        end, {
          buffer = true,
          desc = "Send code blocks up to cursor",
        })

        vim.keymap.set("n", "<leader>rj", function()
          literate.next_block()
        end, {
          buffer = true,
          desc = "Next code block",
        })

        vim.keymap.set("n", "<leader>rk", function()
          literate.prev_block()
        end, {
          buffer = true,
          desc = "Previous code block",
        })
      end,
    })

    -- R: devtools shortcuts + httpgd plot server
    vim.api.nvim_create_autocmd("FileType", {
      pattern = { "r", "rmd", "quarto" },
      callback = function()
        local function rmap(lhs, cmd, desc)
          vim.keymap.set("n", lhs, function()
            send_text(cmd)
          end, { buffer = true, desc = desc })
        end

        rmap("<leader>ro",
          "library(httpgd); hgd(); hgd_browse()",
          "Start httpgd server")
        rmap("<leader>rl", "devtools::load_all()",
          "devtools::load_all()")
        rmap("<leader>rt", "devtools::test()",
          "devtools::test()")
        rmap("<leader>rT",
          "devtools::test_active_file()",
          "devtools::test_active_file()")
        rmap("<leader>rd", "devtools::document()",
          "devtools::document()")
        rmap("<leader>rC", "devtools::check()",
          "devtools::check()")
        rmap("<leader>ri", "devtools::install()",
          "devtools::install()")
      end,
    })

    -- Julia: Pkg/Revise shortcuts
    vim.api.nvim_create_autocmd("FileType", {
      pattern = { "julia" },
      callback = function()
        local function jmap(lhs, cmd, desc)
          vim.keymap.set("n", lhs, function()
            send_text(cmd)
          end, { buffer = true, desc = desc })
        end

        jmap("<leader>rl", "using Revise",
          "using Revise")
        jmap("<leader>rt",
          "using Pkg; Pkg.test()",
          "Pkg.test()")
        jmap("<leader>rA",
          'using Pkg; Pkg.activate(".")',
          'Pkg.activate(".")')
        jmap("<leader>ri",
          "using Pkg; Pkg.instantiate()",
          "Pkg.instantiate()")
        jmap("<leader>rs",
          "using Pkg; Pkg.status()",
          "Pkg.status()")
        jmap("<leader>rT",
          "using TestEnv; TestEnv.activate()",
          "TestEnv.activate()")
        jmap("<leader>rE",
          "using Pkg; Pkg.activate(; temp=true)",
          "Pkg.activate(temp=true)")
      end,
    })

    -- Julia: start MuxDisplay plot pane
    -- Splits nvim pane to create a plot pane below,
    -- then tells the REPL to send plots there.
    -- Requires: MuxDisplay in global Julia env
    --   julia -e 'using Pkg; Pkg.add("MuxDisplay")'
    vim.api.nvim_create_autocmd("FileType", {
      pattern = { "julia" },
      callback = function()
        vim.keymap.set("n", "<leader>ro", function()
          local nvim_pane = vim.env.TMUX_PANE
          if not nvim_pane then
            vim.notify(
              "Not in tmux", vim.log.levels.WARN
            )
            return
          end
          local pane_id = vim.fn.system(
            "tmux split-window -t "
              .. nvim_pane
              .. " -v -d -l 30%"
              .. " -P -F '#{pane_id}'"
          ):gsub("%s+", "")
          send_text(
            "using MuxDisplay; "
              .. "MuxDisplay.enable("
              .. 'target_pane="'
              .. pane_id
              .. '")'
          )
        end, {
          buffer = true,
          desc = "Start MuxDisplay plots",
        })
      end,
    })

  end,
}
