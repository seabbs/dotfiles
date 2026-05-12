const REPL_PACKAGES = [
    :Revise, :Term, :JET, :Cthulhu,
    :CodeTracking, :PrettyPrinting,
    :BenchmarkTools, :TestEnv, :MuxDisplay,
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
    # Only set up display in interactive sessions; scripts get no plot windows
    if isinteractive()
        try
            @eval MuxDisplay.setdisplay!()
        catch
        end
    end
end
