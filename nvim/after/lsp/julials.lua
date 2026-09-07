-- julia-lsp (Mason) needs the project's env path as a positional arg;
-- bare `julia-lsp` prints "Usage: julia-lsp <julia-env-path>" and exits.
--
-- This lives in after/lsp/ rather than lspconfig `opts.servers`: configs
-- from `lsp/` on the runtimepath are merged after `vim.lsp.config()` calls,
-- so nvim-lspconfig's plain `cmd = { "julia-lsp" }` silently won the merge
-- and the server never started. after/lsp/ is merged last.
return {
  cmd = function(dispatchers)
    -- Fall back to the newest default env rather than a hardcoded
    -- version, which goes stale on each upgrade. glob() expands ~
    -- itself; wrapping it in expand() first collapses the matches to
    -- one newline-joined string that then globs to nothing.
    local envs = vim.fn.glob("~/.julia/environments/v*", false, true)
    -- Sort on the numeric version, not the string: v1.9 sorts after
    -- v1.10 lexicographically.
    local function version(path)
      local major, minor = path:match("v(%d+)%.(%d+)$")
      return (tonumber(major) or 0) * 1000 + (tonumber(minor) or 0)
    end
    table.sort(envs, function(a, b)
      return version(a) < version(b)
    end)
    local root = vim.fs.root(0, { "Project.toml", "JuliaProject.toml" })
      or envs[#envs]
    return vim.lsp.rpc.start({ "julia-lsp", root }, dispatchers)
  end,
}
