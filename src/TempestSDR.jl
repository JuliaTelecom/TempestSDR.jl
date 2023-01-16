module TempestSDR

# ----------------------------------------------------
# --- Dependencies 
# ---------------------------------------------------- 
using Reexport 
using FFTW 
using Images
using AbstractSDRs
using Distributed 
using Plots


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
include("MakieRenderer.jl")
@reexport using .MakieRenderer
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
# --- Circular buffer with radio 
# ---------------------------------------------------- 
include("CircularBuffer.jl")
@reexport using .CircularBuffer
# ----------------------------------------------------
# --- Runtime 
# ---------------------------------------------------- 
include("Runtime.jl")
export TempestSDRRuntime
export init_tempestSDR_runtime
export extract_configuration
export coreProcessing
export image_rendering
export stop_processing

end
