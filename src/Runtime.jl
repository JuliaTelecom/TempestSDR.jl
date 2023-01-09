INTERRUPT::Bool = false 


"""" Calculat ethe a priori configuration of the received iage and returns a Video configuration 
""" 
function extract_configuration(csdr::CircularSDR)
    @info "Search screen configuration in given signal."
    print(csdr.sdr)
    # ----------------------------------------------------
    # --- Get long signal to compute metrics 
    # ---------------------------------------------------- 
    # --- Core parameters for the SDR 
    Fs = getSamplingRate(csdr.sdr)
    # --- Number of buffers used for configuration calculation 
    nbBuffer = 3 
    # Instantiate a long buffer to get all the data from the SDR 
    buffSize = length(csdr.buffer)
    sigCorr  = zeros(ComplexF32, nbBuffer * buffSize) 
    # Fill this buffer 
    for n ∈ 1 : nbBuffer 
        sigCorr[ (n-1)*buffSize .+ (1:buffSize)] = circular_sdr_take(csdr)
        print(".")
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
    return finalConfig
end


function coreProcessing(csdr::CircularSDR,theConfig::VideoMode;renderer=:gtk)     # Extract configuration 
    Fs = getSamplingRate(csdr.sdr)
    x_t = theConfig.width    # Number of column
    y_t = theConfig.height   # Number of lines 
    fv  = theConfig.refresh
    # Image format 
    image_size_down = round( Fs /fv) |> Int
    image_size = x_t * y_t |> Int # Size of final image 
    nbIm = length(csdr.buffer) ÷ image_size_down   # Number of image at SDR rate 
    T = Float32
    image_mat = zeros(T,y_t,x_t)
    # ----------------------------------------------------
    # --- Image renderer 
    # ---------------------------------------------------- 
    channelImages = Channel{Array{Float32}}(32)
    @spawnat 2 image_rendering(channelImages,x_t,y_t,renderer)
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
    try 
        #while(true)
        for _ = 1 : 2
            
            sigId = circular_sdr_take(csdr)
            for n in 1:nbIm - 1 
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
                # Putting data  
                circular_put!(channelImages,imageOut)
                #println("."); (mod(n,10) == 0 && println(" "))
                cnt += 1
                yield()
            end
        end
    catch exception 
        rethrow(exception)
    end
    tFinal = time() - tInit 
    rate = Int(floor(nbIm / tFinal))
    @info "Image rate is $rate images per seconds"
    return imageOut
end


function image_rendering(channelImage::Channel,x_t,y_t,renderer=:gtk)
    # Init renderer if Gtk 
    if renderer == :gtk
        screen = initScreenRenderer(y_t,x_t)
    end
    # Loop for rendering 
    global INTERRUPT = false 
    while (INTERRUPT == false)
        # Get a new image 
        imageOut = take!(channelImage)
        #image_mat .= reshape(sigOut[1:Int(x_t*y_t)],Int(x_t),Int(y_t))
        if renderer == :gtk 
            # Using External Gtk display
            displayScreen!(screen,imageOut)
        else 
            # Plot using Terminal 
            terminal(imageOut)
        end
        yield()
    end
end




function stop_processing(csdr)
    global INTERRUPT = true 
    circular_sdr_stop()
    close(csdr.sdr)
end

