using FFTW 
using AbstractSDRs


mutable struct TempestSDRRuntime
    csdr::MultiThreadSDR
    config::VideoMode
    renderer::Symbol
    #screen::AbstractScreenRenderer
    atomicImage::AtomicCircularBuffer
end


function init_tempestSDR_runtime(args...;bufferSize=1024,renderer=:gtk,kw...)
    # --- Configure the SDR remotely
    csdr = open_thread_sdr(args...;kw...,bufferSize)
    # --- Configure the Video 
    # This is a default value here, we maybe can do better
    config = VideoMode(1024,768,60) 
    # --- Init the screen renderer 
    #screen = initScreenRenderer(renderer,config.height,config.width)
    # --- Init the circular buffer 
    atomicImage = AtomicCircularBuffer{Float32}(config.height * config.width,4)
    # --- Create runtime structure 
    #return TempestSDRRuntime(csdr,config,renderer,screen,atomicImage)
    return TempestSDRRuntime(csdr,config,renderer,atomicImage)
end




"""" Calculate the a priori configuration of the received iage and returns a Video configuration 
""" 
function extract_configuration(runtime::TempestSDRRuntime)
    @info "Search screen configuration in given signal."
    # ----------------------------------------------------
    # --- Get long signal to compute metrics 
    # ---------------------------------------------------- 
    # --- Core parameters for the SDR 
    Fs = getSamplingRate(runtime.csdr.sdr)
    # --- Number of buffers used for configuration calculation 
    nbBuffer = 4
    # Instantiate a long buffer to get all the data from the SDR 
    buffSize = length(runtime.csdr.buffer)
    sigCorr  = zeros(Float32, nbBuffer * buffSize) 
    _tmp    = zeros(ComplexF32, buffSize)
    # Fill this buffer 
    for n ∈ 1 : nbBuffer 
        # Getting buffer from radio 
        ThreadSDRs.recv!(_tmp,runtime.csdr)
        println(runtime.csdr.circ_buff.ptr_write.ptr)
        sigCorr[ (n-1)*buffSize .+ (1:buffSize)] .= abs2.(_tmp)
    end
    @info "Calculate the correlation"
    # Calculate the autocorrelation for this buffer 
    (Γ,τ) = calculate_autocorrelation(sigCorr,Fs,0,1/10)
    rates_large,Γ_short_large = zoom_autocorr(Γ,Fs;rate_min=50,rate_max=90)
    # ----------------------------------------------------
    # --- Get the screen rate 
    # ---------------------------------------------------- 
    # ---Find the max 
    (valMax,posMax) = findmax(Γ_short_large)
    posMax_time = 1/rates_large[posMax]
    fv = round(1/ posMax_time;digits=2)
    @info "Position of the max @ $posMax_time seconds [Rate is $fv]"
    # Get the line 
    y_t = let 
        m = findmax(Γ)[2]
        m2 = findmax(Γ[m .+ (1:20)])[2]
        τ = m2 / Fs 
        1 / (fv * τ)
    end
    y_t = 1158
    # ----------------------------------------------------
    # --- Deduce configuration 
    # ---------------------------------------------------- 
    theConfigFound = first(find_closest_configuration(y_t,fv))
    @info "Closest configuration found is $theConfigFound"
    theConfig = theConfigFound[2] # VideoMode config
    theConfig = TempestSDR.allVideoConfigurations["1920x1200 @ 60Hz"]
    finalConfig = VideoMode(theConfig.width,1235,fv)
    @info "Chosen configuration found is $(find_configuration(theConfig)) => $finalConfig"
    # ----------------------------------------------------
    # --- Update runtime 
    # ---------------------------------------------------- 
    runtime.config = finalConfig 
    runtime.atomicImage = AtomicCircularBuffer{Float32}(finalConfig.height * finalConfig.width,4)
    #runtime.screen = initScreenRenderer(screenRenderer,finalConfig.height,finalConfig.width)
    sleep(0.1)
end


function coreProcessing(runtime::TempestSDRRuntime)     # Extract configuration 
    # ----------------------------------------------------
    # --- Overall parameters 
    # ---------------------------------------------------- 
    csdr = runtime.csdr
    theConfig = runtime.config
    # ----------------------------------------------------
    # --- Radio parameters 
    # ---------------------------------------------------- 
    @show Fs = getSamplingRate(runtime.csdr.sdr)
    x_t = theConfig.width    # Number of column
    y_t = theConfig.height   # Number of lines 
    fv  = theConfig.refresh
    #  Signal from radio 
    sigId = zeros(ComplexF32, csdr.circ_buff.buffer.nEch)
    sigAbs = zeros(Float32, csdr.circ_buff.buffer.nEch)
    # Image format 
    @show image_size_down = round( Fs /fv) |> Int
    image_size = x_t * y_t |> Int # Size of final image 
    nbIm = length(csdr.buffer) ÷ image_size_down   # Number of image at SDR rate 
    T = Float32
    image_mat = zeros(T,y_t,x_t)
    # ----------------------------------------------------
    # --- Image renderer 
    # ---------------------------------------------------- 
    imageOut = zeros(T,y_t,x_t)
    # Frame sync 
    sync = SyncXY(image_mat)
    # Measure 
    @info "Ready to process images ($x_t x $y_t)"
    tInit = time()
    ## 
    cnt = 0
    α = 1.0
    τ = 0.0
    do_align = true
    try 
        while(true)
            recv!(sigId,csdr)
            sigAbs .= abs.(sigId)
            for n in 1:nbIm - 4 
                theView = @views sigAbs[n*image_size_down .+ (1:image_size_down)]
                 #Getting an image from the current buffer 
                 image_mat = sig_to_image(theView,y_t,x_t)
                # Frame synchronisation  
                if do_align
                    tup = vsync(image_mat,sync)
                    # Calculate Offset in the image 
                    τ_pixel = (tup[1][2]-1) # Only a vertical sync 
                    τ = Int(floor(τ_pixel / (x_t*y_t)  / fv * Fs))
                    # Rescale image to have the sync image
                    theView = @views sigAbs[τ+n*image_size_down .+ (1:image_size_down)]
                    image_mat = sig_to_image(theView,y_t,x_t)
                end
                # Low pass filter
                # imageOut = (1-α) * imageOut .+ α * image_mat
                imageOut .= image_mat
                 #Putting data  
                 circ_put!(runtime.atomicImage,collect(view(imageOut,:)))
                cnt += 1
            end
            yield()
        end
    catch exception 
        #rethrow(exception)
    end
    tFinal = time() - tInit 
    rate = round(cnt / tFinal;digits=2)
    @info "Process $cnt Images in $tFinal seconds [$rate FPS]"
    return imageOut
end


function image_rendering(runtime::TempestSDRRuntime,screen)
    # ----------------------------------------------------
    # --- Extract parameters 
    # ---------------------------------------------------- 
    x_t = runtime.config.width 
    y_t = runtime.config.height 
    # Init vectors
    _tmp = zeros(Float32,x_t*y_t)
    imageOut = zeros(Float32,y_t,x_t)
    # Loop for rendering 
    cnt = 0
    tInit = time()
    try 
        while (true)
            # Get a new image 
            circ_take!(_tmp,runtime.atomicImage)
            imageOut .= reshape(_tmp,y_t,x_t)
            cnt += 1
            displayScreen!(screen,imageOut)
            sleep(0.01)
            yield()
        end
    catch exception 
    end
    tFinal = time() - tInit 
    @info "Render $cnt Images in $tFinal seconds"
    return cnt
end


