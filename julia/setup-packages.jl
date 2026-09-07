using Pkg

include("startup.jl")

# Only tools used outside the REPL itself. Editor tooling is
# deliberately absent: nvim-dap-julia ships its own Project.toml,
# and Mason's julia-lsp bundles LanguageServer.jl in its own depot,
# so neither needs anything in the default environment.
#
# Julia formatting moved to Runic, installed as a standalone app in
# setup.sh (Pkg.Apps.add("Runic") -> ~/.julia/bin/runic). Runic has
# no style configuration and a single version to pin, so it does not
# belong in the default environment. See issue #76.
dev_only = [
    "Preferences",
    # Jupyter kernel behind molten-nvim. Must live in the *default*
    # environment: the kernel starts with `--project=@.`, so IJulia is
    # only found via the @v#.# entry in LOAD_PATH. A juliaup upgrade
    # moves the default env (v1.11 -> v1.12) and silently leaves IJulia
    # behind in the old one, at which point the kernel dies on startup
    # with "Package IJulia not found in current path".
    "IJulia",
]
all_packages = [String.(REPL_PACKAGES); dev_only]

# Packages previously installed here by hand that the default
# environment should not carry. Documenter and AirspeedVelocity
# belong in a package's own docs/benchmark env; Pluto is better run
# from a temp env; DebugAdapter caps JuliaInterpreter below 0.11 and
# so blocks Revise 3.16; OhMyREPL is unused (startup.jl never loads
# it) and breaks on 1.13; JuliaFormatter was replaced by Runic (see
# setup.sh and issue #76) and is removed so it cannot drift out of
# sync with the pinned pre-commit/CI hook. UnicodePlots is no longer
# loaded by startup.jl, so list it here as well: dropping it from
# REPL_PACKAGES stops it being installed on a fresh machine but would
# otherwise leave it behind in an existing default environment.
unwanted = [
    "AirspeedVelocity", "DebugAdapter", "Documenter",
    "DocumenterTools", "JuliaSyntax", "JuliaFormatter",
    "LanguageServer", "OhMyREPL", "Pluto", "UnicodePlots",
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

# IJulia writes a kernelspec whose argv[0] is the *version-pinned*
# juliaup path (…/julia-1.12.1+0…/bin/julia). juliaup deletes old
# versions on upgrade, so the kernel then fails with ENOENT and molten
# cannot start Julia. Point it at the juliaup launcher instead, which
# tracks the default channel and survives upgrades.
using IJulia
IJulia.installkernel("Julia")
let shim = joinpath(homedir(), ".juliaup", "bin", "julia")
    kernels = joinpath(homedir(), "Library", "Jupyter", "kernels")
    if isdir(kernels) && isfile(shim)
        for dir in readdir(kernels; join = true)
            spec = joinpath(dir, "kernel.json")
            (startswith(basename(dir), "julia") && isfile(spec)) || continue
            text = read(spec, String)
            fixed = replace(
                text,
                r"\"[^\"]*/\.julia/juliaup/julia-[^\"]*/bin/julia\"" => "\"$shim\"",
            )
            fixed == text || write(spec, fixed)
        end
    end
end

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
