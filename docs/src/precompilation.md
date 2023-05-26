## Precompilation notes

One key issue with the application is the initial latency caused by the initial pre-compilation. There are probably some inference issue that can be solved by updating the code (any PR are welcome 😀) but in the meantime speeding up the application can also be of interest.

A simple way is to use the wonderful [Package Compiler application](https://github.com/JuliaLang/PackageCompiler.jl). The goal is to generate a (massive) shared library that can be used in the Julia startup to remove almost all the pre-compilation time. 
If you want to bring the recompilation speed for TempestSDR.jl, use the  following steps 


In the current directory create a file `script_gui.jl` with the following content 

    using TempestSDR 
    tup = gui(;sdr=:radiosim,carrierFreq=764e6,samplingRate=20e6,gain=9,acquisition=0.05);
            

Add Package Compiler as a dependency of your default environment (or create a sandbox environment using a temporary environment)

        julia> using PackageCompiler 
        julia> create_sysimage(["TempestSDRs"], sysimage_path="sys_tempestsdr.so", precompile_execution_file="script_gui.jl")

It will take some time and finally generate a shared library `sys_tempestsdr.so`. You can launch now julia with the pre-compilation option as 

        julia -t auto --sysimage sys_tempestsdr.so


