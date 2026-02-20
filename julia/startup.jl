atreplinit() do repl
    pkgs = [
        :Revise, :Term, :JET, :Cthulhu,
        :CodeTracking, :PrettyPrinting,
        :BenchmarkTools, :TestEnv, :OhMyREPL,
    ]
    for pkg in pkgs
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
