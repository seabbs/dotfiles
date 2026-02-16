-- Proof-of-concept neotest adapter for Julia
-- Runs Pkg.test() and parses Test.jl output
local lib = require("neotest.lib")

---@type neotest.Adapter
local JuliaAdapter = { name = "neotest-julia" }

JuliaAdapter.root = lib.files.match_root_pattern("Project.toml")

---@return boolean
function JuliaAdapter.is_test_file(file_path)
  local normalised = file_path:gsub("\\", "/")
  return normalised:match("test/.*%.jl$") ~= nil
end

function JuliaAdapter.filter_dir(name)
  return name ~= ".git"
    and name ~= "node_modules"
    and name ~= ".julia"
end

---@async
---@return neotest.Tree | nil
function JuliaAdapter.discover_positions(file_path)
  local query = [[
    ;; Match @testset "name" begin ... end
    (macrocall_expression
      (macro_identifier
        (identifier) @_macro (#eq? @_macro "testset"))
      (string_literal) @test.name
      .
      (_) @test.definition
    ) @test.definition

    ;; Match @testset "name" for ... end
    (macrocall_expression
      (macro_identifier
        (identifier) @_macro (#eq? @_macro "testset"))
      (string_literal) @namespace.name
      .
      (for_statement) @namespace.definition
    ) @namespace.definition
  ]]

  local ok, tree = pcall(
    lib.treesitter.parse_positions,
    file_path,
    query,
    { nested_tests = true }
  )
  if ok then
    return tree
  end

  -- Fallback: treat the whole file as a single test
  return lib.treesitter.parse_positions(file_path, "", {
    position_id = function(position)
      return position.path
    end,
  })
end

---@async
---@param args neotest.RunArgs
---@return neotest.RunSpec
function JuliaAdapter.build_spec(args)
  local position = args.tree:data()
  local root = JuliaAdapter.root(position.path)

  if position.type == "dir" or position.type == "file" then
    -- Run all tests via Pkg.test()
    local cmd = string.format(
      'julia --project=%s -e "'
        .. "using Pkg; Pkg.test()"
        .. '"',
      vim.fn.shellescape(root)
    )
    return {
      command = cmd,
      context = { position = position },
    }
  end

  -- For individual test: run the specific file
  local cmd = string.format(
    "julia --project=%s %s",
    vim.fn.shellescape(root),
    vim.fn.shellescape(position.path)
  )
  return {
    command = cmd,
    context = { position = position },
  }
end

---@async
---@param spec neotest.RunSpec
---@param result neotest.StrategyResult
---@param tree neotest.Tree
---@return table<string, neotest.Result>
function JuliaAdapter.results(spec, result, tree)
  local results = {}
  local output = result.output

  -- Read the output file
  local ok, content = pcall(lib.files.read, output)
  if not ok then
    content = ""
  end

  -- Determine pass/fail from exit code
  local status = result.code == 0 and "passed" or "failed"

  -- Mark all positions with the overall result
  for _, node in tree:iter() do
    local pos = node:data()
    results[pos.id] = {
      status = status,
      output = output,
      short = status == "passed"
          and "Tests passed"
        or "Tests failed (see output)",
    }
  end

  return results
end

return JuliaAdapter
