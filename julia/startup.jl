const REPL_PACKAGES = [
    :Revise, :Term, :JET, :Cthulhu,
    :CodeTracking, :PrettyPrinting,
    :BenchmarkTools, :TestEnv, :OhMyREPL,
]

atreplinit() do repl
    for pkg in REPL_PACKAGES
        try
            @eval using $pkg
        catch e
            @warn "error loading $pkg" e
        end
    end
    # Term extras
    try
        @eval install_term_repr()
        @eval install_term_stacktrace()
    catch
    end
end
