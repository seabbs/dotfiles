using Pkg

include("startup.jl")

dev_only = [
    "JuliaFormatter", "LanguageServer",
    "MuxDisplay",
]
all_packages = [String.(REPL_PACKAGES); dev_only]

Pkg.add(all_packages)
Pkg.precompile()
