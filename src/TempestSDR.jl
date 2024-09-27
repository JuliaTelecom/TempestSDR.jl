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


""" Parse Keywords and returns the value based on ARGS. If the parameter is not given, return a default value 
"""
function get_args(arg,default::T) where T
    # Find good argument in list of args 
    goodLine = findall(occursin.(arg,ARGS))

    # If not present, get base value 
    if isempty(goodLine)
        if default == nothing 
            return nothing
        else 
            return default
        end
    else 
        # Get the default type for parsing the string 
        base_ = split(ARGS[goodLine[1]],"=")[end]
        if T == Symbol 
            # For symbol, conversion is a little different 
            return Symbol(base_[2:end]) # Remove : and convert as symbol 
        else 
            return parse(T,base_)
        end
    end
end

""" Create additionnal keywords as a NamedTuple 
"""
function get_kw()
    excep = ["sdr","carrierFreq","samplingRate","gain"]
    # --- Serve as container for final tuple generation 
    inList = ()
    outList = []
    for (k,kargs) ∈ enumerate(ARGS) 
        # Get current name 
        arg_name = split(kargs,"=")[1]
        if any(occursin.(arg_name,excep))
            # already handle by default -> do nothing 
        else 
            # Convert the name as a symbol 
            arg_symb = Symbol(arg_name)
            # Convert value as it is (string as to be \")
            arg_val = Meta.parse(split(kargs,"=")[2])
            # Push in the 2 lists
            inList = (inList...,arg_symb)
            push!(outList,arg_val)
        end
    end
    return NamedTuple{inList}(outList)
end





""" This is a sandbox function to generate an app 
""" 
function julia_main()::Cint 
    #include("config.jl")

    sdr           = get_args("sdr",:radiosim)
    carrierFreq   = get_args("carrierFreq",868e6)
    samplingRate  = get_args("samplingRate",4e6)
    acquisition   = get_args("acquisition",0.05)
    gain          = get_args("gain",10)
    kw  = get_kw()
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
