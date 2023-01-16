INTERRUPT::Bool = false 


mutable struct TempestSDRRuntime
    csdr::CircularSDR 
    config::VideoMode
    renderer::Symbol
    #screen::Union{String,Nothing,Dict}
    screen::Any
    atomicImage::AtomicCircularBuffer
end


function init_tempestSDR_runtime(args...;bufferSize=1024,renderer=:gtk,kw...)
    # --- Configure the SDR 
    csdr = configure_sdr(args...;bufferSize,kw...)
    # --- Configure the Video 
    # This is a default value here, we maybe can do better
    config = VideoMode(1024,768,60) 
    # --- Init the screen renderer 
    if renderer == :gtk
        screen = nothing
    elseif renderer == :makie 
        screen = nothing 
    else 
        screen = "Terminal"
    end
    atomicImage = AtomicCircularBuffer{Float32}(config.height * config.width,4)
    return TempestSDRRuntime(csdr,config,renderer,screen,atomicImage)
end




"""" Calculate the a priori configuration of the received iage and returns a Video configuration 
""" 
function extract_configuration(runtime::TempestSDRRuntime)
    @info "Search screen configuration in given signal."
    print(runtime.csdr.sdr)
    # ----------------------------------------------------
    # --- Get long signal to compute metrics 
    # ---------------------------------------------------- 
    # --- Core parameters for the SDR 
    Fs = getSamplingRate(runtime.csdr.sdr)
    # --- Number of buffers used for configuration calculation 
    nbBuffer = 4
    # Instantiate a long buffer to get all the data from the SDR 
    buffSize = length(runtime.csdr.buffer)
    sigCorr  = zeros(ComplexF32, nbBuffer * buffSize) 
    _tmp    = zeros(ComplexF32, buffSize)
    # Fill this buffer 
    for n ∈ 1 : nbBuffer 
        # Getting buffer from radio 
        circ_take!(_tmp,runtime.csdr.circ_buff)
        println(runtime.csdr.circ_buff.ptr_write.ptr)
        sigCorr[ (n-1)*buffSize .+ (1:buffSize)] .= abs2.(_tmp)
    end
    @info "Calculate the correlation"
    # Calculate the autocorrelation for this buffer 
    #global DUMP_CORR = sigCorr
    #sigCorr = Main.DUMP
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
    if runtime.renderer == :gtk 
        runtime.screen = initScreenRenderer(finalConfig.height,finalConfig.width)
        #body!(wnd, vbox(zeros(finalConfig.height,finalConfig.width))
    elseif runtime.renderer == :makie 
        runtime.screen = MakieRendererScreen(finalConfig.height,finalConfig.width)
    end
    sleep(0.1)
end


function coreProcessing(runtime::TempestSDRRuntime)     # Extract configuration 
    # ----------------------------------------------------
    # --- Overall parameters 
    # ---------------------------------------------------- 
    global INTERRUPT = false 
    csdr = runtime.csdr
    theConfig = runtime.config
    # ----------------------------------------------------
    # --- Radio parameters 
    # ---------------------------------------------------- 
    Fs = getSamplingRate(csdr.sdr)
    x_t = theConfig.width    # Number of column
    y_t = theConfig.height   # Number of lines 
    fv  = theConfig.refresh
    #  Signal from radio 
    sigId = zeros(ComplexF32, csdr.circ_buff.buffer.nEch)
    sigAbs = zeros(Float32, csdr.circ_buff.buffer.nEch)
    # Image format 
    image_size_down = round( Fs /fv) |> Int
    image_size = x_t * y_t |> Int # Size of final image 
    @show nbIm = length(csdr.buffer) ÷ image_size_down   # Number of image at SDR rate 
    T = Float32
    image_mat = zeros(T,y_t,x_t)
    # ----------------------------------------------------
    # --- Image renderer 
    # ---------------------------------------------------- 
    imageOut = zeros(T,y_t,x_t)
    # Frame sync 
    vSync = init_vsync(image_mat)
    # Measure 
    @info "Ready to process images ($x_t x $y_t)"
    tInit = time()
    ## 
    cnt = 0
    α = 0.9
    τ = 0
    do_align = false
    try 
        while(INTERRUPT == false)
            #for _ = 1 : 2
            circ_take!(sigId,csdr.circ_buff)
            sigAbs .= abs2.(sigId)
            for n in 1:1#nbIm - 2 
                theView = @views sigAbs[n*image_size_down .+ (1:image_size_down)]
                 #Getting an image from the current buffer 
                image_mat = transpose(reshape(imresize(theView,image_size),x_t,y_t))
                # Frame synchronisation  
                if do_align
                    tup = vSync(image_mat)
                    # Calculate Offset in the image 
                    τ_pixel = (tup[1][2]-1)
                    τ = Int(floor(τ_pixel / (x_t*y_t)  / fv * Fs))
                    # Rescale image to have the sync image
                    theView = @views sigAbs[τ+n*image_size_down .+ (1:image_size_down)]
                    image_mat = transpose(reshape(imresize(theView,image_size),x_t,y_t))
                end
                # Low pass filter
                imageOut = (1-α) * imageOut .+ α * image_mat
                 #Putting data  
                circ_put!(runtime.atomicImage,imageOut[:])
                cnt += 1
            end
            yield()
        end
    catch exception 
        #rethrow(exception)
    end
    tFinal = time() - tInit 
    rate = Int(floor(nbIm / tFinal))
    @info "Process $cnt Images in $tFinal seconds"
    return imageOut
end


function image_rendering(runtime::TempestSDRRuntime)
    # ----------------------------------------------------
    # --- Extract parameters 
    # ---------------------------------------------------- 
    x_t = runtime.config.width 
    y_t = runtime.config.height 
    # Init vectors
    _tmp = zeros(Float32,x_t*y_t)
    imageOut = zeros(Float32,y_t,x_t)
    # Loop for rendering 
    global INTERRUPT = false 
    cnt = 0
    while (INTERRUPT == false)
        # Get a new image 
        circ_take!(_tmp,runtime.atomicImage)
        imageOut .= reshape(_tmp,y_t,x_t)
        cnt += 1
        if runtime.renderer == :gtk 
            # Using External Gtk display
            displayScreen!(runtime.screen,imageOut)
        elseif runtime.renderer == :makie 
            displayMakieScreen!(runtime.screen,imageOut)
        else 
            # Plot using Terminal 
            terminal(imageOut)
        end
    end
    return cnt
end


function stop_processing(runtime::TempestSDRRuntime)
    global INTERRUPT = true 
    circ_stop(runtime.csdr)
    close(runtime.csdr.sdr)
end

