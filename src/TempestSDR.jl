module TempestSDR

# ----------------------------------------------------
# --- Dependencies 
# ---------------------------------------------------- 
using Reexport 
using FFTW 
using Images
using AbstractSDRs
using Distributed 
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
export extract_configuration
export stop_processing

export coreProcessing
function coreProcessing(sigId::Vector{T},Fs,theConfig::VideoMode;renderer=:gtk) where T
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
    @show image_size_down = round( Fs /fv) |> Int
    @show image_size = x_t * y_t |> Int # Size of final image 
    nbIm = length(sigId) ÷ image_size_down ÷ decimation  # Number of image at SDR rate 
    #@show nbIm = 100
    # Containers
    #theView = zeros(T, image_size_down  )
    image_mat = zeros(T,y_t,x_t)
    # Clojure 
    #resampler! = init_resampler(T,image_size_down,upCoeff)
    #out = zeros(T,(image_size_down+2) * upCoeff)
    # Init renderer 
    if renderer == :gtk
        screen = initScreenRenderer(y_t,x_t)
    end
    imageOut = zeros(T,y_t,x_t)
    # Frame sync 
    vSync = init_vsync(image_mat)
    # Measure time 
    @info "Ready to process $nbIm images ($x_t x $y_t)"
    tInit = time()
    ## 
    cnt = 0
    α = 0.9
    τ = 0
    for n in 1:nbIm
        theView = @views sigId[n*image_size_down .+ (1:image_size_down)]
        # Getting an image from the current buffer 
        image_mat = transpose(reshape(imresize(theView,image_size),x_t,y_t))
        # Frame synchronisation  
        tup = vSync(image_mat)
        # Calculate Offset in the image 
        τ_pixel = (tup[1][2]-1)
        τ = Int(floor(τ_pixel / (x_t*y_t)  / fv * Fs))
        # Rescale image to have the sync image
        theView = @views sigId[τ+n*image_size_down .+ (1:image_size_down)]
        image_mat = transpose(reshape(imresize(theView,image_size),x_t,y_t))
        # Low pass filter
        imageOut = (1-α) * imageOut .+ α * image_mat
        #println("."); (mod(n,10) == 0 && println(" "))
        #image_mat .= reshape(sigOut[1:Int(x_t*y_t)],Int(x_t),Int(y_t))
        if renderer == :gtk 
            # Using External Gtk display
            (mod(cnt,decimation) == 0) && (displayScreen!(screen,image_mat))
        else 
            # Plot using Terminal 
            terminal(imageOut)
        end
        cnt += 1
    end
    tFinal = time() - tInit 
    rate = Int(floor(nbIm / tFinal))
    @info "Image rate is $rate images per seconds"
    return imageOut
end



end
