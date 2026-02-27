return {
  {
    "nvim-neotest/neotest",
    dependencies = {
      "nvim-neotest/neotest-python",
      "shunsambongi/neotest-testthat",
    },
    opts = {
      adapters = {
        ["neotest-python"] = {
          runner = "pytest",
        },
        ["neotest-testthat"] = {},
      },
    },
    config = function(_, opts)
      -- Inject the local Julia adapter
      opts.adapters = opts.adapters or {}
      table.insert(
        opts.adapters,
        require("neotest-julia")
      )

      -- Let LazyVim's test.core handle the rest
      -- by calling the original config
      local neotest_ns =
        vim.api.nvim_create_namespace("neotest")
      vim.diagnostic.config({
        virtual_text = {
          format = function(diagnostic)
            return diagnostic.message
              :gsub("\n", " ")
              :gsub("\t", " ")
              :gsub("%s+", " ")
              :gsub("^%s+", "")
          end,
        },
      }, neotest_ns)

      -- Process adapter configs (same as LazyVim)
      if opts.adapters then
        local adapters = {}
        for name, config in pairs(opts.adapters) do
          if type(name) == "number" then
            if type(config) == "string" then
              config = require(config)
            end
            adapters[#adapters + 1] = config
          elseif config ~= false then
            local ok, adapter = pcall(require, name)
            if ok then
              if
                type(config) == "table"
                and not vim.tbl_isempty(config)
              then
                if adapter.setup then
                  adapter.setup(config)
                elseif adapter.adapter then
                  adapter.adapter(config)
                  adapter = adapter.adapter
                end
              end
              adapters[#adapters + 1] = adapter
            end
          end
        end
        opts.adapters = adapters
      end

      require("neotest").setup(opts)
    end,
  },
}
