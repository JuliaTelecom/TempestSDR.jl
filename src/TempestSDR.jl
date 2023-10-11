module TempestSDR

# ----------------------------------------------------
# --- Dependencies 
# ---------------------------------------------------- 
using Reexport 
# 
# ----------------------------------------------------
# --- Dat file managment
# ---------------------------------------------------- 
include("DatBinaryFiles.jl")
@reexport using .DatBinaryFiles
# ----------------------------------------------------
# --- Spectrum 
# ---------------------------------------------------- 
include("GetSpectrum.jl")
@reexport using .GetSpectrum
# ----------------------------------------------------
# --- Demodulation 
# ---------------------------------------------------- 
include("Demodulation.jl")
export amDemod
export invert_amDemod
# ----------------------------------------------------
# --- Resampling methods 
# ---------------------------------------------------- 
include("Resampler.jl")
@reexport using .Resampler
# ----------------------------------------------------
# --- Image renderer
# ---------------------------------------------------- 
include("ScreenRenderer.jl")
@reexport using .ScreenRenderer
# ----------------------------------------------------
# --- Video configurations 
# ---------------------------------------------------- 
include("VideoConfigurations.jl")
# ----------------------------------------------------
# --- Autocorrelation utils
# ---------------------------------------------------- 
include("Autocorrelations.jl")
@reexport using .Autocorrelations
# ----------------------------------------------------
# --- Frame synchronisation 
# ---------------------------------------------------- 
include("FrameSynchronisation.jl")
@reexport using .FrameSynchronisation
# ----------------------------------------------------
# --- Radio in specific core
# ---------------------------------------------------- 
include("AtomicAbstractSDRs.jl")
@reexport using .AtomicAbstractSDRs
# ----------------------------------------------------
# --- Runtime 
# ---------------------------------------------------- 
include("GUI.jl")
export gui
export start_runtime
export stop_runtime




""" This is a sandbox function to generate an app 
""" 
function julia_main()::Cint 
    include("config.jl")
    # This should import all we need 
    tup = gui(;
	  sdr,
	  carrierFreq,
	  samplingRate,
	  gain,
	  acquisition,
	  kw...
	  )
    return 0
end


end
