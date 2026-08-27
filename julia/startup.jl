const REPL_PACKAGES = [
    :Revise, :Term, :JET, :Cthulhu,
    :CodeTracking, :PrettyPrinting,
    :BenchmarkTools, :TestEnv, :MuxDisplay,
    :TestItemRunner, :UnicodePlots,
]

# Loaded in the background so the prompt (and Pkg mode) is usable
# immediately instead of blocking for the ~60-90s these packages can
# take to precompile their extensions on every fresh process.
atreplinit() do repl
    @async begin
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
        try
            @eval MuxDisplay.setdisplay!()
        catch
        end
    end
end
