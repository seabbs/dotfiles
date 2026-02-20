using Pkg

packages = [
    "Revise",
    "Term",
    "JET",
    "Cthulhu",
    "CodeTracking",
    "PrettyPrinting",
    "BenchmarkTools",
    "TestEnv",
    "OhMyREPL",
    "JuliaFormatter",
    "LanguageServer",
]

Pkg.add(packages)
Pkg.precompile()
