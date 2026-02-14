using Pkg: Pkg
atreplinit() do repl
  # Load Revise if it is installed
  try
    @eval using Revise
  catch e
    @warn "error while importing Revise" e
  end
  # Load Term if it is installed
  try
    @eval using Term
    @eval install_term_repr()
    @eval install_term_stacktrace()
  catch e
    @warn "error while importing Term" e
  end
  # Load JET if it is installed
  try
    @eval using JET
  catch e
    @warn "error while importing JET" e
  end
  # Load Cthulhu if it is installed
  try
    @eval using Cthulhu
  catch e
    @warn "error while importing Cthulhu" e
  end
  # Load CodeTracking if it is installed
  try
    @eval using CodeTracking
  catch e
    @warn "error while importing CodeTracking" e
  end
  # Load PrettyPrinting if it is installed
  try
    @eval using PrettyPrinting
  catch e
    @warn "error while importing PrettyPrinting" e
  end
  # Load BenchmarkTools if it is installed
  try
    @eval using BenchmarkTools
  catch e
    @warn "error while importing BenchmarkTools" e
  end
  # Load TestEnv if it is installed
  try
    @eval using TestEnv
  catch e
    @warn "error while importing TestEnv" e
  end
  try
    @eval using OhMyREPL
  catch e
    @warn "error whilst importing OhMyREPL" e
  end
end
