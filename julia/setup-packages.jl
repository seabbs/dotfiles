using Pkg

include("startup.jl")

dev_only = ["JuliaFormatter", "LanguageServer"]
all_packages = [String.(REPL_PACKAGES); dev_only]

Pkg.add(all_packages)

# JuliaC CLI (installed as an app, not a package)
Pkg.Apps.add("JuliaC")

Pkg.precompile()
