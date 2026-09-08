import REPL

const REPL_PACKAGES = [
    :Revise, :Term, :JET, :Cthulhu,
    :CodeTracking, :PrettyPrinting,
    :BenchmarkTools, :TestEnv, :MuxDisplay,
    :TestItemRunner,
]

# Ctrl+R runs the same television channel the shell uses
# (tv/cable/julia-history.toml), so history search behaves the same in
# the Julia REPL as it does in zsh. This replaces Julia's built-in
# Ctrl+R prefix search; that is still reachable by typing a prefix and
# pressing Up. tv needs the terminal out of raw mode while it draws, and
# the line redrawn afterwards.
function tv_history_search(s)
    term = REPL.LineEdit.terminal(s)
    selection = ""
    REPL.Terminals.raw!(term, false)
    print(stdout, "\n")
    try
        selection = readchomp(`tv julia-history`)
    catch
        # non-zero exit just means the picker was dismissed
    finally
        REPL.Terminals.raw!(term, true)
    end
    REPL.LineEdit.refresh_line(s)
    # The channel joins multi-line entries with a literal \n so a leading
    # comment cannot swallow the rest of the entry; restore real newlines.
    selection = replace(selection, "\\n" => "\n")
    isempty(selection) || REPL.LineEdit.edit_insert(s, selection)
    return :done
end

# Loaded in the background so the prompt (and Pkg mode) is usable
# immediately instead of blocking for the ~60-90s these packages can
# take to precompile their extensions on every fresh process.
atreplinit() do repl
    # Must run before the interface is built, and synchronously -- the
    # package loading below is deliberately deferred, this is not.
    if Sys.which("tv") !== nothing
        try
            repl.interface = REPL.setup_interface(
                repl;
                extra_repl_keymap = Dict{Any, Any}(
                    "^R" => (s, o...) -> tv_history_search(s),
                ),
            )
        catch e
            @warn "could not bind tv history search" e
        end
    end

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
        # MuxDisplay is loaded but not activated here: enabling it needs
        # a target pane, which only the editor knows. nvim's <leader>Ro
        # (nvim/lua/plugins/slime.lua) splits the pane and sends the
        # MuxDisplay.enable call with that pane id.
    end
end
