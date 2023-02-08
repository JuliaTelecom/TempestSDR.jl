using FFTW 
using AbstractSDRs
using Makie, GLMakie 


# ----------------------------------------------------
# --- Global variables 
# ---------------------------------------------------- 
# Flags 
FLAG_CONFIG_UPDATE::Bool = false 
FLAG_HEATMAP::Bool = true 
# Configuration
CONFIG::VideoMode =  VideoMode(1024,768,60) 
SAMPLING_RATE::Float64 = 20e6
# Channels 
channelImage::Channel = Channel{Matrix{Float32}}(16) 

# ----------------------------------------------------
# --- Channel for image tranfert between renderer and processor
# ---------------------------------------------------- 
@inline function non_blocking_put!(image)
    global channelImage
    if channelImage.n_avail_items == channelImage.sz_max 
        ## This is full 
        take!(channelImage) 
    end 
    put!(channelImage,image)
end 

mutable struct TempestSDRRuntime
    csdr::MultiThreadSDR
end

""" Create the virtual or real SDR for data transmission. The SDR uses AbstractSDRs API and is set to be launched in a dedicated thread 
"""
function init_tempestSDR_runtime(args...;bufferSize=1024,kw...)
    global CONFIG, SAMPLING_RATE
    # --- Configure the SDR remotely
    csdr = open_thread_sdr(args...;kw...,bufferSize)
    SAMPLING_RATE = getSamplingRate(csdr.sdr)
    # --- Configure the Video 
    # This is a default value here, we maybe can do better
    CONFIG = TempestSDR.allVideoConfigurations["1920x1200 @ 60Hz"]
    return TempestSDRRuntime(csdr)
end




"""" Calculate the a priori configuration of the received iage and returns a Video configuration 
""" 
function extract_configuration(runtime::TempestSDRRuntime)
    global CONFIG, FLAG_HEATMAP, SAMPLING_RATE
    @info "Search screen configuration in given signal."
    # ----------------------------------------------------
    # --- Get long signal to compute metrics 
    # ---------------------------------------------------- 
    # --- Core parameters for the SDR 
    Fs = SAMPLING_RATE
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
        w = (runtime.csdr.circ_buff.ptr_write.ptr)
        r = (runtime.csdr.circ_buff.ptr_read.ptr)
        @info "Atomic write $w \t Atomic read $r "
        sigCorr[ (n-1)*buffSize .+ (1:buffSize)] .= abs2.(_tmp)
    end
    @info "Calculate the correlation"
    # Calculate the autocorrelation for this buffer 
    (Γ,τ) = calculate_autocorrelation(sigCorr,Fs,0,1/10)
    rates_refresh,Γ_refresh = zoom_autocorr(Γ,Fs;rate_min=50,rate_max=90)
    # ----------------------------------------------------
    # --- Get the screen rate 
    # ---------------------------------------------------- 
    # ---Find the max 
    (valMax,posMax) = findmax(Γ_refresh)
    posMax_time = 1/rates_refresh[posMax]
    fv = round(1/ posMax_time;digits=2)
    @info "Selected refresh rate is $fv"
    # ----------------------------------------------------
    # --- Screen configuration 
    # ---------------------------------------------------- 
    N = 1000
    Γ_yt = Γ_refresh[posMax .+ (1:N)]
    rates_yt = range(0,step=1/Fs,length=N)
    select_y = findmax(Γ_yt)[2] / Fs
    y_t = delay2yt(select_y,fv)
    @info "Number of lines is $y_t"
    # ----------------------------------------------------
    # --- Prepare output
    # ---------------------------------------------------- 
    # Size of image will be changed
    FLAG_HEATMAP = true
    # Update configuration based on max a priori 
    config = find_closest_configuration(y_t,fv) |> dict2video
    CONFIG = config 
    #CONFIG.height = y_t 
    CONFIG.refresh = fv
    @info "Screen configuration is $CONFIG"
    #@show CONFIG = finalConfig
    return rates_refresh,Γ_refresh,rates_yt,Γ_yt,fv,select_y # TODO Here returns this and in future put in channel ?
end

""" Switch from a correlation lag (in second or couple delay in samples and Fs) to a number of pixel estimation
"""
function delay2yt(τ,fv) 
    return round( 1 / (fv * τ))
end 
function delay2yt(index,Fs,fv) 
    return delay2yt(index/Fs,fv)
end


""" Listener to select the refresh rate based on the correlation. 
It draws a vertical lines at the selected location and a text pop up 
"""
function listener_refresh(screen,rates_refresh,Γ_refresh,Fs)
    global CONFIG, FLAG_CONFIG_UPDATE
    # ----------------------------------------------------
    # --- Find scene with correlation 
    # ---------------------------------------------------- 
    fig = screen.figure   # Figure 
    ax  = fig.content[2]  # Axis for correlation  
    t   = ax.scene[2]     # Second index is the text 
    vL  = ax.scene[3]     # Third index is the vline 
    # ----------------------------------------------------
    # --- Add the listener 
    # ---------------------------------------------------- 
    on(events(fig.scene).mousebutton) do mp
        if mp.button == Mouse.left
            if is_mouseinside(ax.scene)
                select_f,amp = mouseposition(ax.scene)
                # Adding the annotation on the plot 
                t.position = (select_f,amp)
                t[1] = " $select_f"
                t.visible = true
                # Print a vertical line at this location 
                vL[1] = select_f # FIXME Why int ?
                # Update configuration
                FLAG_CONFIG_UPDATE = true
                CONFIG.refresh = select_f
                # Update the lines plot
                N = 1000
                posMax = argmin(abs.(rates_refresh .- select_f))
                Γ_yt = Γ_refresh[posMax .+ (1:N)]
                r = range(0,step=1/Fs,length=N)
                plot_findyt(screen,r,Γ_yt,0.0) 
            end
        end
    end
end

function listener_yt(screen)
    global CONFIG, FLAG_CONFIG_UPDATE, SAMPLING_RATE
    # ----------------------------------------------------
    # --- Find scene with correlation 
    # ---------------------------------------------------- 
    fig = screen.figure   # Figure 
    ax  = fig.content[3]  # Axis for correlation  for y_t 
    t   = ax.scene[2]     # Second index is the text 
    vL  = ax.scene[3]     # Third index is the vline 
    # ----------------------------------------------------
    # --- Add the listener 
    # ---------------------------------------------------- 
    on(events(fig.scene).mousebutton) do mp
        if mp.button == Mouse.left
            if is_mouseinside(ax.scene)
                select_y,amp = mouseposition(ax.scene)
                # Adding the annotation on the plot 
                t.position = (select_y,amp)
                t.visible = true
                vL[1] = select_y
                # Print a vertical line at this location 
                #vL[1] = round(select_f) # FIXME Why int ?
                # Change selection of f to a number of lines 
                fv = CONFIG.refresh
                y_t = delay2yt(select_y,fv)
                t[1] = " $(y_t)"
                # Config will be changed 
                FLAG_CONFIG_UPDATE = true
                # Find the closest configuration 
                theConfig = find_closest_configuration(y_t,fv) |> dict2video
                # Keep the rate as we have chosen 
                theConfig.refresh = fv
                theConfig.height= y_t
                CONFIG = theConfig
            end
        end
    end
end



""" Add the correlation plot to the Makie figure 
"""
function plot_findRefresh(screen,rates,Γ,Fs,fv=0.0) 
    ScreenRenderer._plotInteractiveCorrelation(screen.axis_refresh,rates,Γ,fv,:gold2) 
    listener_refresh(screen,rates,Γ,Fs)
    #lines!(ax,rates,Γ)
end

function plot_findyt(screen,rates,Γ,fv=0.0) 
    ScreenRenderer._plotInteractiveCorrelation(screen.axis_yt,rates,Γ,fv,:turquoise4) 
    listener_yt(screen)
    #lines!(ax,rates,Γ)
end


""" Init the buffer associated to image rendering. Necessary at the beginning of the processing routine or each time the rendering configuration is updated 
"""
function update_image_containers(theConfig::VideoMode,Fs) 
    # Unpack config 
    x_t = theConfig.width    # Number of column
    y_t = theConfig.height   # Number of lines 
    fv  = theConfig.refresh
    # Size of images 
    image_size_down = round( Fs /fv) |> Int
    # Init arrays 
    imageOut = zeros(Float32,y_t,x_t)
    image_mat = zeros(Float32,y_t,x_t)

    return (x_t,y_t,image_size_down,imageOut,image_mat)

end

function coreProcessing(runtime::TempestSDRRuntime)     # Extract configuration 
    global CONFIG, FLAG_CONFIG_UPDATE, SAMPLING_RATE, channelImage
    # ----------------------------------------------------
    # --- Overall parameters 
    # ---------------------------------------------------- 
    csdr = runtime.csdr
    # ----------------------------------------------------
    # --- Radio parameters 
    # ---------------------------------------------------- 
    Fs = SAMPLING_RATE

    #  Signal from radio 
    sigId = zeros(ComplexF32, csdr.circ_buff.buffer.nEch)
    sigAbs = zeros(Float32, csdr.circ_buff.buffer.nEch)
    # ----------------------------------------------------
    # --- Image 
    # ---------------------------------------------------- 
    (x_t,y_t,image_size_down,imageOut,image_mat) = update_image_containers(CONFIG,Fs)
    nbIm = length(csdr.buffer) ÷ image_size_down   # Number of image at SDR rate 
    # ----------------------------------------------------
    # --- Image renderer 
    # ---------------------------------------------------- 
    # Frame sync 
    sync = SyncXY(image_mat)
    # Measure 
    @info "Ready to process images ($x_t x $y_t)"
    tInit = time()
    ## 
    cnt = 0
    α = Float32(1.0)
    τ = 0.0
    do_align = true
    try 
        while(true)
            # Look for configuration update 
            if FLAG_CONFIG_UPDATE == true 
                (x_t,y_t,image_size_down,imageOut,image_mat) = update_image_containers(CONFIG,Fs)
                nbIm = length(csdr.buffer) ÷ image_size_down   # Number of image at SDR rate 
                sync = SyncXY(image_mat)
                FLAG_CONFIG_UPDATE = false 
                @show CONFIG
            end
            # Receive samples from SDR
            recv!(sigId,csdr)
            sigAbs .= abs.(sigId)
            for n in 1:nbIm - 4 
                theView = @views sigAbs[n*image_size_down .+ (1:image_size_down)]
                #Getting an image from the current buffer 
                image_mat = sig_to_image(theView,y_t,x_t)
                # Frame synchronisation  
                if do_align == true 
                    tup = vsync(image_mat,sync)
                    image_mat = circshift(image_mat,(-tup[1],-tup[2]))
                end
                # Low pass filter
                imageOut = (1-α) * imageOut .+ α * image_mat
                #Putting data  
                non_blocking_put!(imageOut)
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



function image_rendering(screen)
    global channelImage, FLAG_HEATMAP
    # ----------------------------------------------------
    # --- Extract parameters 
    # ---------------------------------------------------- 
    fig = screen.figure   # Figure 
    ax  = fig.content[1]  # Axis for heatmap
    # Loop for rendering 
    cnt = 0
    tInit = time()
    imageDisplay = zeros(Float32,600,800)
    try 
        while (true)
            # Get a new image 
            imageOut = take!(channelImage)::Matrix{Float32}
            imageDisplay .= downgradeImage(imageOut)
            cnt += 1
            if FLAG_HEATMAP == true 
                # We need to redraw the heatmap 
                screen.plot = ScreenRenderer._plotHeatmap(ax,imageDisplay)
                FLAG_HEATMAP = false
            else 
                displayScreen!(screen,imageDisplay)
            end
            sleep(0.01)
            yield()
        end
    catch exception 
        rethrow(exception)
    end
    tFinal = time() - tInit 
    @info "Render $cnt Images in $tFinal seconds"
    return cnt
end


