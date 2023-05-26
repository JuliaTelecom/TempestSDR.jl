## How it works 

First, you have to install the package through package manager 

        julia> using Pkg 
        julia> Pkg.add("TempestSDR")

Or directly `] add TempestSDR` in the Pkg mode of the Julia REPL. There are a bunch a dependencies so it makes take a little time to install. 

Then after some black magic Pkg does you should be able to launch the graphical user interface with this command 


        julia> using TempestSDR 
        julia> TempestSDR.gui(; sdr = :radiosim,
        carrierFreq = 764e6,
        sampingRate=20e6, 
        gain = 20,
        )                  


Some remarks here 
- `sdr` keyword corresponds to  the type of SDR you use and have to be supported by AbstrctSDRs. If you want to use some binary file, set the sdr as `radiosim` which is the virtual radio front-end used in AbstractSDRs 
- `carrierFreq` is the carrier frequency of the SDR and should be tuned to a potential leakage (for instance  742.5 MHz) 
- `samplingRate` is the band of the SDR. The larger is ofen the better and we find that 20MHz is a very good trade-off. If your SDR does not support this bandwidth try lower values (with often lower image reconstruction)
- `gain` is the gain of the radio. If you don't know how what to put, try a value of 0 and do not hesitate to increase it :) 
- `buffer::Vector{ComplexF32}` (optional) if you want to provide the GUI samples you have already acquire. It has only a sense if you use a virtual backend `radiosim` (otherwise samples from SDR will be used).



