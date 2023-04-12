 # Create image with
  # using Pkg; Pkg.activate("."); using PackageCompiler; PackageCompiler.create_sysimage(["TempestSDR"];sysimage_path="ExampleTempest.so",precompile_execution_file="production/script_compilation.jl");
 
  # Launch julia with
  # $ julia -t auto --sysimage="./ExampleTempest.so" -O3
 
using TempestSDR 

tup = gui(;sdr=:radiosim,carrierFreq=764e6,samplingRate=20e6,gain=9,acquisition=0.05,addr="192.168.40.2")    

