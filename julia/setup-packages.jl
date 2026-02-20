using Pkg

include("startup.jl")

dev_only = ["JuliaFormatter", "LanguageServer"]
all_packages = [String.(REPL_PACKAGES); dev_only]

Pkg.add(all_packages)
Pkg.precompile()
