# This file automatically configure the current project to use all the avaliable Julia workers. Be sure julia is launched with `-p x` with `x`the number of desired workers

using Distributed 
if nprocs() > 1 
    # Using package manager and worker manager 
    @everywhere using Distributed,Pkg 
    # Getting the name of the current active project 
    PROJECT_NAME = Symbol(Pkg.project().name)
    # --- Activation for all workers
    @everywhere Pkg.activate(".")
    # --- Using package in all workers
    @everywhere @eval using $PROJECT_NAME
end

