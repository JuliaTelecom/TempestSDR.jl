module TempestSDR

# ----------------------------------------------------
# --- Dependencies 
# ---------------------------------------------------- 
using Reexport 
using FFTW 
using Images

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
# ----------------------------------------------------
# --- Video configurations 
# ---------------------------------------------------- 
include("VideoConfigurations.jl")
# ----------------------------------------------------
# --- Autocorrelation utils
# ---------------------------------------------------- 
include("Autocorrelations.jl")
@reexport using .Autocorrelations

export coreProcessing

function coreProcessing(sigId::Vector{T},Fs,theConfig::VideoMode) where T
    # Extract configuration 
    x_t = theConfig.width    # Number of column
    y_t = theConfig.height   # Number of lines 
    fv  = theConfig.refresh
    # Decim 
    # To ensure we have enough throughput, we will decimate the number of processed images 
    decimation = 3
    # Upsampling parameters
    new_sampling_frequency = x_t * y_t * fv
    upCoeff = round(new_sampling_frequency / Fs) |> Int
    practical_freq = upCoeff * new_sampling_frequency
    @info "New sampling frequency is $practical_freq Hz"
    # Image format 
    image_size_down = round( Fs /fv) |> Int
    image_size = x_t * y_t |> Int # Size of final image 
    nbIm = length(sigId) ÷ image_size_down ÷ decimation  # Number of image at SDR rate 
    #@show nbIm = 100
    # Containers
    #theView = zeros(T, image_size_down  )
    image_mat = zeros(T,y_t,x_t)
    # Clojure 
    #resampler! = init_resampler(T,image_size_down,upCoeff)
    #out = zeros(T,(image_size_down+2) * upCoeff)
    # Init renderer 
    screen = initScreenRenderer(y_t,x_t)
    imageOut = zeros(T,y_t,x_t)
    # Measure time 
    @info "Ready to process $nbIm images ($x_t x $y_t)"
    tInit = time()
    ## 
    cnt = 0
    α = 0.001
    for n in 1:nbIm
        theView = @views sigId[n*image_size_down .+ (1:image_size_down)]
        #resampler!(out,theView)
        #Main.infiltrate(@__MODULE__, Base.@locals, @__FILE__, @__LINE__)
        #naiveResampler(out,theView,upCoeff)
        image_mat = transpose(reshape(imresize(theView,image_size),x_t,y_t))
        # Low pass filter
        imageOut = (1-α) * imageOut .+ α * image_mat
        #println("."); (mod(n,10) == 0 && println(" "))
        #image_mat .= reshape(sigOut[1:Int(x_t*y_t)],Int(x_t),Int(y_t))
        (mod(cnt,decimation) == 0) && (displayScreen!(screen,image_mat))
        cnt += 1
        #cnt += decimation
    end
    tFinal = time() - tInit 
    rate = Int(floor(nbIm / tFinal))
    @info "Image rate is $rate images per seconds"
    return screen
end

end
