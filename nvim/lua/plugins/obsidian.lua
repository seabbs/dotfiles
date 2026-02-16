return {
  -- Remap snacks notification history to free up <leader>n
  {
    "folke/snacks.nvim",
    keys = {
      {
        "<leader>n",
        false,
      },
      {
        "<leader>uN",
        function()
          Snacks.picker.notifications()
        end,
        desc = "Notification History",
      },
    },
  },

  {
    "obsidian-nvim/obsidian.nvim",
    version = "*",
    lazy = true,
    ft = "markdown",
    dependencies = {
      "nvim-lua/plenary.nvim",
    },
    opts = {
      workspaces = {
        {
          name = "notes",
          path = vim.fn.expand(
            "~/Library/CloudStorage/"
              .. "GoogleDrive-s.e.abbott12@gmail.com/"
              .. "My Drive/cloud/apps/obsidian/notes"
          ),
        },
      },

      -- Use new command syntax (:Obsidian <subcommand>)
      legacy_commands = false,

      -- Daily notes
      daily_notes = {
        folder = "dailies",
        date_format = "%Y-%m-%d",
      },

      -- Templates
      templates = {
        folder = "templates",
        date_format = "%Y-%m-%d",
        time_format = "%H:%M",
      },

      -- Note ID: use title slug, not timestamp prefix
      note_id_func = function(title)
        if title ~= nil then
          return title
            :gsub(" ", "-")
            :gsub("[^A-Za-z0-9-]", "")
            :lower()
        end
        local suffix = ""
        for _ = 1, 4 do
          suffix = suffix
            .. string.char(math.random(65, 90))
        end
        return tostring(os.time()) .. "-" .. suffix
      end,

      preferred_link_style = "wiki",

      -- Completion via blink.cmp
      completion = {
        blink = true,
        min_chars = 2,
      },

      -- Picker
      picker = {
        name = "snacks.pick",
      },

      -- Mappings (buffer-local for markdown files)
      mappings = {
        ["gf"] = {
          action = function()
            return require("obsidian").util.gf_passthrough()
          end,
          opts = {
            noremap = false,
            expr = true,
            buffer = true,
          },
        },
        ["<leader>ch"] = {
          action = function()
            return require("obsidian").util.toggle_checkbox()
          end,
          opts = { buffer = true },
        },
        ["<cr>"] = {
          action = function()
            return require("obsidian").util.smart_action()
          end,
          opts = { buffer = true, expr = true },
        },
      },
    },
    keys = {
      { "<leader>n", nil, desc = "+notes" },
      {
        "<leader>nn",
        "<cmd>Obsidian new<cr>",
        desc = "New note",
      },
      {
        "<leader>no",
        "<cmd>Obsidian open<cr>",
        desc = "Open in Obsidian",
      },
      {
        "<leader>ns",
        "<cmd>Obsidian quick_switch<cr>",
        desc = "Switch note",
      },
      {
        "<leader>nf",
        "<cmd>Obsidian search<cr>",
        desc = "Search notes",
      },
      {
        "<leader>nd",
        "<cmd>Obsidian today<cr>",
        desc = "Today's daily note",
      },
      {
        "<leader>nD",
        "<cmd>Obsidian dailies<cr>",
        desc = "Browse daily notes",
      },
      {
        "<leader>nb",
        "<cmd>Obsidian backlinks<cr>",
        desc = "Backlinks",
      },
      {
        "<leader>nt",
        "<cmd>Obsidian tags<cr>",
        desc = "Tags",
      },
      {
        "<leader>nl",
        "<cmd>Obsidian links<cr>",
        desc = "Links in buffer",
      },
      {
        "<leader>nT",
        "<cmd>Obsidian template<cr>",
        desc = "Insert template",
      },
      {
        "<leader>np",
        "<cmd>Obsidian paste_img<cr>",
        desc = "Paste image",
      },
      {
        "<leader>nr",
        "<cmd>Obsidian rename<cr>",
        desc = "Rename note",
      },
      {
        "<leader>nm",
        function()
          local client = require("obsidian").get_client()
          local vault = tostring(client.dir)
          vim.cmd("edit " .. vault .. "/projects/Meta.md")
        end,
        desc = "Open Meta/TODO",
      },
    },
  },
}
