using AbstractSDRs
using Makie, GLMakie 
using Base.Threads
using GLMakie: Observable, Observables 
Callback = Observables.ObserverFunction
# ----------------------------------------------------
# --- Constant 
# ---------------------------------------------------- 
# The final image size 
const RENDERING_SIZE = (600,800)

# Observable linked to number of lines  
OBS_yt   = Observable{Int}(1530)
OBS_box_yt   = Observable{Int}(1530)
# Observable for refresh 
OBS_fv   = Observable{Float64}(60.0)
OBS_box_fv   = Observable{Float64}(60.0)
# Observable for sampling frequency
OBS_Fs   = Observable{Float64}(20e6)
# Observable on what we do 
OBS_Task = Observable{Int}(0)
# Observable on new correlations 
OBS_Corr = Observable{Bool}(false)
OBS_Corr_yt = Observable{Bool}(false)
# Start // Stop 
OBS_running = Observable{Bool}(false)
# Flags 
FLAG_CONFIG_UPDATE  = Observable{Bool}(false)
# Video Config
VIDEO_CONFIG::VideoMode = VideoMode(1024,768,60) 
# Correlations 
rates_refresh::Vector{Float32} = []
Γ_refresh::Vector{Float32} = []
rates_yt::Vector{Float32} = []
Γ_yt::Vector{Float32} = []
# Channel for renderer 
channelImage::Channel = Channel{Matrix{Float32}}(16) 

mutable struct GUI 
    fig::Any 
    heatmap::Any 
end


# ----------------------------------------------------
# --- Methods 
# ---------------------------------------------------- 
function extract_configuration(csdr::MultiThreadSDR)
    @info "Search screen configuration in given signal."
    # ----------------------------------------------------
    # --- Get long signal to compute metrics 
    # ---------------------------------------------------- 
    # --- Core parameters for the SDR 
    Fs = OBS_Fs[]::Float64
    # --- Number of buffers used for configuration calculation 
    nbBuffer = 4
    # Instantiate a long buffer to get all the data from the SDR 
    buffSize = length(csdr.buffer)
    sigCorr  = zeros(Float32, nbBuffer * buffSize) 
    _tmp    = zeros(ComplexF32, buffSize)
    # Fill this buffer 
    for n ∈ 1 : nbBuffer 
        # Getting buffer from radio 
        ThreadSDRs.recv!(_tmp,csdr)
        w = (csdr.circ_buff.ptr_write.ptr)
        r = (csdr.circ_buff.ptr_read.ptr)
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
    fv = 1/posMax_time
    fvR = round(fv;digits=2)
    @info "Selected refresh rate is $fvR"
    # ----------------------------------------------------
    # --- Prepare output
    # ---------------------------------------------------- 
    return rates_refresh,Γ_refresh,fv # TODO Here returns this and in future put in channel ?
end

""" Init the buffer associated to image rendering. Necessary at the beginning of the processing routine or each time the rendering configuration is updated 
"""
function update_image_containers(theConfig::VideoMode,Fs::Float64) 
    # Unpack config 
    x_t = theConfig.width::Int    # Number of column
    y_t = theConfig.height::Int   # Number of lines 
    fv  = theConfig.refresh::Float64
    # Size of images 
    image_size_down = round( Fs /fv) |> Int
    return (x_t,y_t,image_size_down)
end


function getImageDuration(theConfig::VideoMode,Fs::Float64)::Int64 
    x_t = theConfig.width::Int    # Number of column
    y_t = theConfig.height::Int   # Number of lines 
    fv  = theConfig.refresh::Float64
    # Size of images 
    return image_size_down = round( Fs /fv) |> Int
end 

@inline function non_blocking_put!(image)
    global channelImage
    if channelImage.n_avail_items == channelImage.sz_max 
        ## This is full 
        take!(channelImage) 
    end 
    put!(channelImage,image)
end 

function coreProcessing(csdr::MultiThreadSDR)
    # 
    global RENDERING_SIZE 
    #
    samplingRate_real = getSamplingRate(csdr.sdr)
    OBS_Fs[] = samplingRate_real
    #  Signal from radio 
    sigId = zeros(ComplexF32, csdr.circ_buff.buffer.nEch)
    sigAbs = zeros(Float32, csdr.circ_buff.buffer.nEch)
    # ----------------------------------------------------
    # --- Image 
    # ---------------------------------------------------- 
    image_size_down = getImageDuration(VIDEO_CONFIG,samplingRate_real)
    image_mat = zeros(Float32,RENDERING_SIZE...)
    imageOut  = zeros(Float32,RENDERING_SIZE...)
    sync = SyncXY(image_mat)
    nbIm = length(csdr.buffer) ÷ image_size_down   # Number of image at SDR rate 
    @show x_t = VIDEO_CONFIG.width |> Int 
    @show y_t = VIDEO_CONFIG.height |> Int
    cnt = 0
    do_align = true 
    α = 1.0

    tInit = time()
    try 
        while(true)
            #Look for configuration update 
            if FLAG_CONFIG_UPDATE[] == true 
                image_size_down = getImageDuration(VIDEO_CONFIG,samplingRate_real)
                nbIm = length(csdr.buffer) ÷ image_size_down   # Number of image at SDR rate 
                FLAG_CONFIG_UPDATE[] = false 
                @show VIDEO_CONFIG
                x_t = VIDEO_CONFIG.width
                y_t = VIDEO_CONFIG.height
            end
            # Receive samples from SDR
            recv!(sigId,csdr)
            sigAbs .= abs.(sigId)
            if OBS_Task[] == 2 
                for n in 1:nbIm - 4 
                    theView = @views sigAbs[n*image_size_down .+ (1:image_size_down)]
                    ##Getting an image from the current buffer 
                    image_mat .= (sig_to_image(theView,y_t,x_t) |> downgradeImage)
                    # Frame synchronisation  
                    if do_align == true 
                        tup = vsync(image_mat,sync)
                        image_mat .= circshift(image_mat,(-tup[1],-tup[2]))
                    end
                    # Low pass filter
                    imageOut .= (1-α) * imageOut .+ α * image_mat
                    #Putting data  
                    non_blocking_put!(imageOut)
                    cnt += 1
                end
            end
        end
    catch exception 
        #rethrow(exception)
    end
    tFinal = time() - tInit 
    rate = round(cnt / tFinal;digits=2)
    @info "Process $cnt Images in $tFinal seconds [$rate FPS]"
    return imageOut
end

function image_rendering(gui)
    global channelImage
    # ----------------------------------------------------
    # --- Extract parameters 
    # ---------------------------------------------------- 
    # Loop for rendering 
    cnt = 0
    tInit = time()
    imageOut = zeros(Float32,RENDERING_SIZE...)
    try 
        while (true)
            if OBS_Task[] == 2
                # Get a new image 
                imageOut .= take!(channelImage)::Matrix{Float32}
                cnt += 1
                gui.heatmap[1] = collect(imageOut') 
                yield()
            else 
                sleep(0.1)
            end
        end
    catch exception 
        #rethrow(exception)
    end
    tFinal = time() - tInit 
    @info "Render $cnt Images in $tFinal seconds"
    return cnt
end

""" Switch from a correlation lag (in second or couple delay in samples and Fs) to a number of pixel estimation
"""
function delay2yt(τ,fv) 
    return round( 1 / (fv * τ))
end 
function delay2yt(index,Fs,fv) 
    return delay2yt(index/Fs,fv)
end

""" Switch from a yt size to the associated lag of the autocorr 
"""
function yt2index(yt,Fs,fv)
    return round(Fs/(fv*yt))
end
function yt2delay(yt,fv)
    return 1/(fv*yt)
end

# GUI Utils 
""" Update tooltip of the axis `content` present as a subscene of index `sceneIndex` 
"""
function updateToolTip(content,sceneIndex,value,displayVal = nothing)
    if isnothing(displayVal) 
        displayVal = round(value;digits=2)
    end
    lM  = maximum(content.yaxis.tickvalues[])  # max value for position
    lm  = minimum(content.yaxis.tickvalues[])
    lp = lm + 0.8 * (lM-lm)
    # max value for position
    content.scene[sceneIndex].visible = true
    content.scene[sceneIndex].position = (value,lp)
    content.scene[sceneIndex][1] = "  $(displayVal)"
end

# ----------------------------------------------------
# --- Runtime 
# ---------------------------------------------------- 
function start_runtime()
    # Recall global variables 
    global VIDEO_CONFIG
    global rates_refresh, Γ_refresh
    global rates_yt, Γ_yt

    # ----------------------------------------------------
    # --- Create GUI 
    # ---------------------------------------------------- 
     # --- Define the Grid Layout 
     figure = Figure(backgroundcolor=:lightgrey,resolution=(1800,1200))
     panelImage = figure[1:6, 1:3] = GridLayout()
     panelRefresh = figure[7, 1:4] = GridLayout()
     panelYt = figure[8, 1:4] = GridLayout()
     panelInfo = figure[1,4]
     # --- Add a first image
     axIm = Makie.Axis(panelImage[1,1])
     m = randn(Float32,RENDERING_SIZE...)
     plot_obj = ScreenRenderer._plotHeatmap(axIm,m)
     #plot_obj = image(m)
     axIm.yreversed = true
     # --- Display the first lines for correlation 
     axT = Makie.Axis(panelRefresh[1,1])
     delay = collect(50 : 90)
     corr = randn(Float32,length(delay))
     ScreenRenderer._plotInteractiveCorrelation(axT,delay,corr,OBS_fv[],:turquoise4)
     # The zoomed correlation 
     axZ = Makie.Axis(panelYt[1,1])
     ScreenRenderer._plotInteractiveCorrelation(axZ,delay,corr,0.0,:gold4)
     # The information panel 
     gc = panelInfo[1,1]
     # Run mode 
     btnStart = Button(gc, label = "RUN MODE", fontsize=35)
     # Refresh panel 
     l_fv = Label(panelInfo[2,1], "Refresh Rate",tellwidth = false,fontsize=24)
     boxRefresh = Textbox(panelInfo[2,2], placeholder = "Refresh Rate",validator = Float64, tellwidth = false,fontsize=24)
     # Panel for yt 
     l_yt = Label(panelInfo[3,1], "Height size",tellwidth = false,fontsize=24)
     boxYt = Textbox(panelInfo[3,2], placeholder = "yt",validator = Int64, tellwidth = false,fontsize=24)
    panelInfo[3, 3] = buttongrid = GridLayout(tellwidth = false)
    btnYt_plus = Button(buttongrid[1,1], label = "+", tellwidth = false,fontsize=14)
    btnYt_minus = Button(buttongrid[2,1], label = "-", tellwidth = false,fontsize=16)
    rowgap!(buttongrid,0.15)
    # Display the image 
    display(figure)
    # Create objet 
    gui = GUI(figure,plot_obj)


    # ----------------------------------------------------
    # --- Instantiate radio 
    # ---------------------------------------------------- 
     # Parameters 
    carrierFreq  = 764e6
    samplingRate = 20e6
    gain         = 50 
    acquisition   = 0.50
    @info "Loading data"
    local completePath = "/Users/Robin/data_tempest/testX310.dat"
    sigRx = readComplexBinary(completePath,:single)
    nbS = Int(round(acquisition * samplingRate))
    # Radio 
    csdr = open_thread_sdr(:radiosim,carrierFreq,samplingRate,gain;addr="usb:0.9.5",bufferSize=nbS,buffer=sigRx,packetSize=nbS)

   

    # ----------------------------------------------------
    # --- Launch threads 
    # ---------------------------------------------------- 
    task_producer   = Threads.@spawn start_thread_sdr(csdr)
    task_consummer  = Threads.@spawn coreProcessing(csdr)
    task_rendering  = @async image_rendering(gui)

    # Instantiate callback list
    list_cb = Callback[]

    # ----------------------------------------------------
    # --- Run modes 
    # ---------------------------------------------------- 
    """ RUN mode : toggle the mode 
    -> Start the correlation task 
    -> Or Stop the processing task 
    """
    cb_click = on(btnStart.clicks) do clk 
        OBS_running[] = !OBS_running[] 
        if OBS_running[] == true 
            btnStart.label = "PAUSE" 
            OBS_Task[] = 1
        else 
            btnStart.label = "RUN !"
            OBS_Task[] = 0
        end
    end
    push!(list_cb,cb_click)


    """ Task mode 
    -> 1 : Correlation and auto config 
    -> 2 : Processing mode for image rendering 
    """
    cb_task::Callback = on(OBS_Task) do task 
        if task == 1 
            # ----------------------------------------------------
            # --- Configuration task 
            # ---------------------------------------------------- 
            rates_refresh,Γ_refresh,fv = extract_configuration(csdr)
            OBS_Corr[] = true
            OBS_Task[] = 2
            OBS_fv[]   = fv
        elseif task == 2 
            # ----------------------------------------------------
            # --- Image processing task 
            # ---------------------------------------------------- 
            @info "Processing NOW !!!"
        end
    end
    push!(list_cb,cb_task)

    """ Correlation for refresh has been re-calculated, we need to
    -> Update the refresh correlation plots 
    -> Update refresh line for ylim adaptation
    -> Update textbox 
    """
    cb_corr = on(OBS_Corr) do cc 
        # Redraw the correlation 
        delete!(gui.fig.content[2],gui.fig.content[2].scene[3])
        lines!(gui.fig.content[2],rates_refresh,Γ_refresh,color=:gold)
        # Put the lines at proper location and update the text
        gui.fig.content[2].scene[2][1] = OBS_fv[]
        #
        updateToolTip(gui.fig.content[2],1,OBS_fv[])
        OBS_Corr_yt[] = true 

    end
    push!(list_cb,cb_corr)


    """ Click on refresh-Correlation leads to interactive update of the value of the refresh rate of the screen 
    -> Update the value of fv 
    """
    cb_interactive_corr = on(events(gui.fig.content[2].scene).mousebutton) do mp
        if mp.button == Mouse.left
            if is_mouseinside(gui.fig.content[2].scene)
                select_f,_ = mouseposition(gui.fig.content[2].scene)
                # Update configuration
                @show OBS_fv[] = select_f
            end
        end
    end
    push!(list_cb,cb_interactive_corr)

    """ Edit text of rate => Update fv
    """ 
    cb_box_fv = on(boxRefresh.stored_string) do fv 
        rr = parse(Float64, fv)
        OBS_fv[] = rr 
    end
    push!(list_cb,cb_box_fv)

    """ [OBSERVABLE] OBS_fv is modified (from textbox or correlation) 
    -> Update the tooltip and the line position 
    -> Update the refresh box 
    -> Alert planelYt Update the panelYt to realign the zoomed correlation 
    """
    cb_fv = on(OBS_fv) do fv 
        FLAG_CONFIG_UPDATE[] = true
        # Put the lines at proper location and update the text
        gui.fig.content[2].scene[2][1] = OBS_fv[]
        # Refresh the text 
        updateToolTip(gui.fig.content[2],1,OBS_fv[])
        # Refresg the refresh textbox
        @info "Update refresh tool"
        boxRefresh.displayed_string = string(round(OBS_fv[];digits=2))
        # Update yt plot 
        OBS_Corr_yt[] = true 
    end
    push!(list_cb,cb_fv)

    """ Update panelYt  
    -> Redraw the correlation 
    -> Add the line at the chosen yt 
    -> Add the tooltip 
    """ 
    cb_corr_yt = on(OBS_Corr_yt) do cc 
        N = 1000
        fv = OBS_fv[]::Float64
        posFv = argmin(abs.(rates_refresh .- fv)) # Get the posityion of the selection, from which the zoom is performed
        Γ_yt = Γ_refresh[posFv .+ (1:N)]
        rates_yt = range(0,step=1/OBS_Fs[],length=N)
        τ_y_t = delay2yt(OBS_yt[],fv) # Delay in s associated to yt
       # Redraw the correlation 
        delete!(gui.fig.content[3],gui.fig.content[3].scene[3])
        lines!(gui.fig.content[3],rates_yt,Γ_yt,color=:turquoise4)
        # Put the lines at proper location and update the text
        gui.fig.content[3].scene[2][1] = τ_y_t
        #
        updateToolTip(gui.fig.content[3],1,τ_y_t,OBS_yt[])
    end
    push!(list_cb,cb_corr_yt)

    """ Click on refresh-Correlation leads to interactive update of the value of number of lines 
    -> Update the value of yt
    """
    cb_interactive_corr_yt = on(events(gui.fig.content[3].scene).mousebutton) do mp
        if mp.button == Mouse.left
            if is_mouseinside(gui.fig.content[3].scene)
                τ_y_t,_ = mouseposition(gui.fig.content[3].scene)
                # Switch to y_t config 
                y_t = delay2yt(τ_y_t,OBS_fv[])
                # Update configuration
                OBS_yt[] =y_t
            end
        end
    end
    push!(list_cb,cb_interactive_corr_yt)


    """ Click on + increment yt 
    """ 
    cb_click_plus = on(btnYt_plus.clicks) do clk 
        OBS_yt[] += 1
    end 
    push!(list_cb,cb_click_plus) 
    """ Click on - decrement yt 
    """ 
    cb_click_minus = on(btnYt_minus.clicks) do clk 
        OBS_yt[] -= 1
    end 
    push!(list_cb,cb_click_minus) 

    """ Edit text of yt => Update yt 
    """ 
    cb_box_yt = on(boxYt.stored_string) do yt 
        rr = parse(Int64, yt)
        OBS_yt[] = rr 
    end
    push!(list_cb,cb_box_yt)


    """ [OBSERVABLE] OBS_yt is modified (from textbox or correlation) 
    -> Update the tooltip and the line position 
    -> Update the yt box 
    """
    cb_yt = on(OBS_yt) do yt 
        τ_y_t = yt2delay(OBS_yt[],OBS_fv[])
        FLAG_CONFIG_UPDATE[] = true
        # Put the lines at proper location and update the text
        gui.fig.content[3].scene[2][1] = τ_y_t
        # Refresh the text 
        updateToolTip(gui.fig.content[3],1,τ_y_t,OBS_yt[])
        # Refresh the yt textbox
        boxYt.displayed_string = string(OBS_yt[])
    end
    push!(list_cb,cb_yt)


    """ [OBSERVABLE] Config is updated ! Update its fields 
    """ 
    cb_update = on(FLAG_CONFIG_UPDATE) do f 
        if FLAG_CONFIG_UPDATE[] == true 
            # Find the closest configuration for yt 
            video = dict2video(find_closest_configuration(OBS_yt[],OBS_fv[]))
            VIDEO_CONFIG.width  = video.width 
            VIDEO_CONFIG.height = OBS_yt[] 
            VIDEO_CONFIG.refresh = OBS_fv[]
        end
    end
    push!(list_cb,cb_update)

    return (;gui,csdr,task_producer,task_consummer,task_rendering,list_cb)
   
end

function stop_runtime(tup)
    @info "Stopping all threads"
    OBS_Task[] = 0
    # SDR safe stop 
    @async Base.throwto(tup.task_producer,InterruptException())
    #sleep(1)
    # Task stop 
    @async Base.throwto(tup.task_consummer,InterruptException())
    @async Base.throwto(tup.task_rendering,InterruptException())
    # Safely close radio 
    close(tup.csdr)
    # Destroy the GUI
    for cb in tup.list_cb
        # Remove all observables from GUI
        off(cb) 
    end
    #tup.list_cb = nothing
    GC.gc()
    destroy(tup.gui)
    return nothing
end


function destroy(gui::GUI)
    sc = GLMakie.Makie.getscreen(gui.fig.scene)
    if !isnothing(sc)
        GLMakie.destroy!(sc)
    end 
end

