using Pkg

include("startup.jl")

# Only tools used outside the REPL itself. Editor tooling is
# deliberately absent: nvim-dap-julia ships its own Project.toml,
# and Mason's julia-lsp bundles LanguageServer.jl in its own depot,
# so neither needs anything in the default environment.
dev_only = [
    "JuliaFormatter", "Preferences",
]
all_packages = [String.(REPL_PACKAGES); dev_only]

# Packages previously installed here by hand that the default
# environment should not carry. Documenter and AirspeedVelocity
# belong in a package's own docs/benchmark env; Pluto is better run
# from a temp env; DebugAdapter caps JuliaInterpreter below 0.11 and
# so blocks Revise 3.16; OhMyREPL is unused (startup.jl never loads
# it) and breaks on 1.13.
unwanted = [
    "AirspeedVelocity", "DebugAdapter", "Documenter",
    "DocumenterTools", "JuliaSyntax", "LanguageServer",
    "OhMyREPL", "Pluto",
]

installed = keys(Pkg.project().dependencies)
to_remove = filter(in(installed), unwanted)
isempty(to_remove) || Pkg.rm(to_remove)

Pkg.add(all_packages)

# Pkg.add leaves already-installed packages at their current
# version, so upgrade explicitly. This is what pulls Revise past
# 3.16 once DebugAdapter is out of the way.
Pkg.update()

# Let Revise reload struct definitions from edited files.
# Needs Julia 1.12+ (world-age semantics) and Revise 3.13+.
# Off by default in 3.16 because the type scan used to be slow;
# 3.16 cut that to ~13ms, and 3.17 flips the default. Until then
# set it explicitly, or struct edits silently fail to reload.
# Keep Revise >= 3.16 or the scan costs ~5.5s at every startup.
using Preferences
set_preferences!(
    Base.UUID("295af30f-e4ad-537b-8983-00126c2a3abe"),  # Revise
    "revise_structs" => true;
    force = true,
)

Pkg.precompile()

# AgentREPL keeps a warm Julia session for Claude Code agents over MCP
# (claude/settings.json starts it, claude/skills/julia-repl says how to
# use it). Unregistered, so dev it from GitHub. It lives in its own
# shared environment because the server runs as
# `julia --project=@AgentREPL`, which needs no absolute path and so
# survives Julia upgrades and works on both macOS and Linux.
Pkg.activate("AgentREPL"; shared = true)
Pkg.develop(url = "https://github.com/samtalki/AgentREPL.jl")
Pkg.instantiate()
Pkg.precompile()
Pkg.activate()
