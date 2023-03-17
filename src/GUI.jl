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
# Observable for image LPF 
OBS_α    = Observable{Float32}(0.1)
# Observable on what we do 
OBS_Task = Observable{Int}(0)
# Observable on new correlations 
OBS_Corr = Observable{Bool}(false)
OBS_Corr_yt = Observable{Bool}(false)
# Start // Stop 
OBS_running = Observable{Bool}(false)
# Flags 
FLAG_CONFIG_UPDATE  = Observable{Bool}(false)
FLAG_KILL::Bool = false
# Video Config
VIDEO_CONFIG::VideoMode = VideoMode(1024,768,60) 
# Correlations 
rates_refresh::Vector{Float32} = []
Γ_refresh::Vector{Float32} = []
# Channel for renderer 
channelImage::Channel = Channel{Matrix{Float32}}(2) 

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
    Fs = getSamplingRate(csdr.sdr)
    # --- Number of buffers used for configuration calculation 
    nbBuffer = 12
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


function getImageDuration(theConfig::VideoMode,Fs::Number)::Int64 
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
    nEch = csdr.circ_buff.buffer.nEch
    sigId = zeros(ComplexF32, nEch)
    sigAbs = zeros(Float32, nEch)
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
    # Record buffers 
    nbBuffer = 10 # in second 
    cntBuffer = 0 # Ident for file 
    recordBuffer = zeros(ComplexF32, nbBuffer * length(sigId)) 

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
            # Gain the LPS val 
            α = OBS_α[]::Float32
            if OBS_Task[] == 2 
                # Receive samples from SDR
                recv!(sigId,csdr)
                sigAbs .= amDemod(sigId)
                for n in 1:nbIm 
                    theView = @views sigAbs[(n-1)*image_size_down .+ (1:image_size_down)]
                    ##Getting an image from the current buffer 
                    image_mat .= (sig_to_image(theView,y_t,x_t) |> downgradeImage)
                    # Frame synchronisation  
                    if do_align == true 
                        tup = vsync(image_mat,sync)
                        image_mat .= circshift(image_mat,(-tup[1],-tup[2]))
                    end
                    # Low pass filter
                    imageOut .= α * imageOut .+ (1-α) * image_mat
                    #Putting data  
                    non_blocking_put!(imageOut)
                    cnt += 1
                end
            elseif OBS_Task[] == 3 
                # Record signal 
                for n ∈ 1 : nbBuffer 
                    recv!(sigId,csdr)
                    recordBuffer[((n-1)*nEch).+(1:nEch)] .= sigId 
                end 
                theName = "dumpIQ_$(cntBuffer).dat"
                writeComplexBinary(recordBuffer,theName)
                cntBuffer += 1
                OBS_Task[] = 2
            else 
                 # Sleepy mode
                sleep(0.1);
                yield()
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

""" Switch from MHz to Hz for carrier frequency 
"""
HztoMHz(x) = round(x / 1e6;digits=2)
MHztoHz(x) = x * 1e6 


""" Get the description of the video configuration 
""" 
function getDescription(video::VideoMode) 
    dict = find_closest_configuration(video.width,video.refresh) |> first
    return ("$(dict.first)","$(dict.second)")
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
function start_runtime(sdr,carrierFreq,samplingRate,gain,acquisition;kw...)
    # Recall global variables 
    global VIDEO_CONFIG
    global FLAG_KILL
    global rates_refresh, Γ_refresh
    #global rates_yt, Γ_yt

    # ----------------------------------------------------
    # --- Create GUI 
    # ---------------------------------------------------- 
     # --- Define the Grid Layout 
     figure = Figure(backgroundcolor=:lightgrey,resolution=(1800,1200))
     panelImage = figure[1:2, 1:3] = GridLayout()
     panelRefresh = figure[3, 1:4] = GridLayout()
     panelYt = figure[4, 1:4] = GridLayout()
     panelInfo = figure[1,4] = GridLayout()
     # --- Add a first image
     axIm = Makie.Axis(panelImage[1,1])
     m = randn(Float32,RENDERING_SIZE...)
     plot_obj = ScreenRenderer._plotHeatmap(axIm,m)
     #plot_obj = image(m)
     axIm.yreversed = true
     # --- Display the first lines for correlation 
     axT = Makie.Axis(panelRefresh[1,1])
     delay = collect(50 : 90)
     corr = zeros(Float32,length(delay))
     ScreenRenderer._plotInteractiveCorrelation(axT,delay,corr,OBS_fv[],:turquoise4)
     # The zoomed correlation 
     axZ = Makie.Axis(panelYt[1,1])
     ScreenRenderer._plotInteractiveCorrelation(axZ,delay,corr,0.0,:gold4)
     # Run mode 
     btnStart = Button(panelInfo[1,1], label = "START", fontsize=35,halign=:center,tellwidth=false,tellheight=true,cornerradius=12,buttoncolor=RGBf(0.67, 0.91, 0.77))
    # Panel to Exit
    bttnKill = Button(panelInfo[1,2], label = "Exit", fontsize=40,halign=:center,tellwidth=true,tellheight=false,cornerradius=12,buttoncolor=RGBf(0.96, 0.71, 0.69))
     # Refresh panel 
     l_fv = Label(panelInfo[2,1], "Refresh Rate",tellwidth = false,fontsize=24,halign=:left)
     boxRefresh = Textbox(panelInfo[2,2], placeholder = "Refresh Rate",validator = Float64, tellwidth = false,fontsize=24,halign=:left)
     # Panel for yt 
     l_yt = Label(panelInfo[3,1], "Height size",tellwidth = false,fontsize=24,halign=:left)
     boxYt = Textbox(panelInfo[3,2], placeholder = "$(OBS_yt[])",validator = Int64, tellwidth = false,fontsize=24,halign=:left)
    panelInfo[3, 3] = buttongrid = GridLayout(tellwidth = false,halign=:left)
    btnYt_plus = Button(buttongrid[1,1], label = "+", tellwidth = false,fontsize=24,halign=:left,width=20)
    btnYt_minus = Button(buttongrid[2,1], label = "-", tellwidth = false,fontsize=24,halign=:left,width=20)
    rowgap!(buttongrid,0.15)
    # Panel to redo correlation
    bttnCorr = Button(panelInfo[4,1], label = "Correlate !", fontsize=35,halign=:left,cornerradius=12)
    # Slider for Radio gain 
     l_gain = Label(panelInfo[5,1], "Radio Gain",tellwidth = false,fontsize=24,halign=:left)
    sliderGain = Slider(panelInfo[5,2], range = 0:1:50, startvalue = 3)
    # SDR carrier frequency 
    l_freq = Label(panelInfo[6,1], "Carrier freq (MHz)",tellwidth = false,fontsize=24,halign=:left)
    boxFreq = Textbox(panelInfo[6,2], placeholder = "$(HztoMHz(carrierFreq))",validator = Float64, tellwidth = false,fontsize=24,halign=:left)
    # SDR carrier frequency 
    l_samp = Label(panelInfo[7,1], "Sample Rate (MHz)",tellwidth = false,fontsize=24,halign=:left)
    boxSamp = Textbox(panelInfo[7,2], placeholder = "$(HztoMHz(samplingRate))",validator = Float64, tellwidth = false,fontsize=24,halign=:left)
    # LPF coefficient 
     l_filt = Label(panelInfo[8,1], "Low pass filter",tellwidth = false,fontsize=24,halign=:left)
     sliderLPF = Slider(panelInfo[8,2], range = Float32.(0:0.05:1), startvalue = Float32(OBS_α[]))
     # Panel for configuration 
     l_config = Label(panelInfo[9,1], "Configuration ",tellwidth = false,fontsize=24,halign=:left)
     l_config_out = Label(panelInfo[9,2], "$(getDescription(VIDEO_CONFIG)[1])",tellwidth = false,fontsize=24,halign=:left)
     # Panel for configuration 
     #l_config = Label(panelInfo[9,1], "Frame size (theo) ",tellwidth = false,fontsize=24,halign=:left)
     #l_config_th = Label(panelInfo[9,2], "$(getDescription(VIDEO_CONFIG)[2])",tellwidth = false,fontsize=24,halign=:left)
   # Panel to redo correlation
    bttnRecord = Button(panelInfo[4,2], label = "Record !", fontsize=35,halign=:left,cornerradius=12,buttoncolor=RGBf(0.56, 0.71, 0.69))

    # Display the image 
    display(figure)
    # Create objet 
    gui = GUI(figure,plot_obj)


    # ----------------------------------------------------
    # --- Instantiate radio 
    # ---------------------------------------------------- 
     # Parameters 

     nbS = Int(round(acquisition * samplingRate))
     if sdr == :radiosim 
         @info "Loading data"
         local completePath = "/Users/Robin/data_tempest/testX310.dat"
         sigRx = readComplexBinary(completePath,:single)
     else 
         sigRx = zeros(ComplexF32,nbS)
     end 
     # Radio 
     csdr = open_thread_sdr(sdr,carrierFreq,samplingRate,gain;bufferSize=nbS,buffer=sigRx,packetSize=nbS,kw...)

   

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
            btnStart.label = "START"
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
        posFv = argmin(abs.(rates_refresh[1:end-N] .- fv)) # Get the position of the selection, from which the zoom is performed
        Γ_yt = Γ_refresh[posFv .+ (1:N)]
        rates_yt = range(0,step=1/OBS_Fs[],length=N)
        @show τ_y_t = yt2delay(OBS_yt[],fv) # Delay in s associated to yt
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
    and update the textbox 
    """ 
    cb_update = on(FLAG_CONFIG_UPDATE) do f 
        if FLAG_CONFIG_UPDATE[] == true 
            # Find the closest configuration for yt 
            video = dict2video(find_closest_configuration(OBS_yt[],OBS_fv[]))
            VIDEO_CONFIG.width  = video.width 
            VIDEO_CONFIG.height = OBS_yt[] 
            VIDEO_CONFIG.refresh = OBS_fv[]
            # Display it the textbox
            l_config_out.text = getDescription(VIDEO_CONFIG)[1]
            #l_config_th.text = getDescription(VIDEO_CONFIG)[2]
        end
    end
    push!(list_cb,cb_update)


    """ Click on Correlate redo the correlation task 
    """ 
    cb_click_corr = on(bttnCorr.clicks) do clk 
        OBS_Task[] = 1 
    end
    push!(list_cb,cb_click_corr)


    """ Click on record to record the signal 
    """ 
    cb_click_record = on(bttnRecord.clicks) do clk 
        OBS_Task[] = 3 
    end
    push!(list_cb,cb_click_record)

    """ Click on Kill change the Observer 
    -> Kill is done 
    """ 
    cb_kill = on(bttnKill.clicks) do clk 
        FLAG_KILL = true
    end
    push!(list_cb,cb_kill)


    """ Slider of the gain tune the SDR gain 
    """ 
    cb_sliderGain  =on(sliderGain.value) do gain 
        updateGain!(csdr.sdr,gain) 
    end
    push!(list_cb,cb_sliderGain)


    """ Slider for LPF 
    """ 
    cb_slider_lpf = on(sliderLPF.value) do α 
        OBS_α[] = α 
    end 
    push!(list_cb,cb_slider_lpf)

    """ Edit text of carrier frequency => Update SDR 
    Note that we handle MHz and Hz 
    """ 
    cb_box_freq = on(boxFreq.stored_string) do freq
        # Get the float in MHz 
        f_MHz = parse(Float64, freq)
        # Switch to Hz for SDR update 
        f_Hz = MHztoHz(f_MHz) 
        # Update the SDR 
        # Need to get the actual RF freq
        f_Hz = updateCarrierFreq!(csdr.sdr,f_Hz)
        # Get the value in MHz 
        f_MHz = HztoMHz(f_Hz)
        # Update the box 
        boxFreq.displayed_string = string(f_MHz)
    end
    push!(list_cb,cb_box_freq)

    """ Edit text of carrier frequency => Update SDR 
    Note that we handle MHz and Hz 
    """ 
    cb_box_samp = on(boxSamp.stored_string) do freq
        # Get the float in MHz 
        f_MHz = parse(Float64, freq)
        # Switch to Hz for SDR update 
        f_Hz = MHztoHz(f_MHz) 
        # Update the SDR 
        # Need to get the actual RF freq
        f_Hz = updateSamplingRate!(csdr.sdr,f_Hz)
        # Get the value in MHz 
        f_MHz = HztoMHz(f_Hz)
        # Update the observable 
        OBS_Fs[] = f_Hz 
        # Update the box 
        boxSamp.displayed_string = string(f_MHz)
    end
    push!(list_cb,cb_box_samp)



    tup = (;gui,csdr,task_producer,task_consummer,task_rendering,list_cb)
    return tup
end


function gui(;
        sdr=:radiosim,
        carrierFreq  = 764e6,
        samplingRate = 20e6,
        gain         = 50, 
        acquisition  = 0.50,
        kw...
    ) 
    global FLAG_KILL
    # Start the runtime 
    tup = start_runtime(sdr,carrierFreq,samplingRate,gain,acquisition;kw...)
    @async begin 
        while(FLAG_KILL == false) 
            sleep(0.1) 
            yield() 
        end 
        # Stop processing
        OBS_Task[] = 0
        sleep(0.5)
        # Get the signal 
        stop_runtime(tup)
        FLAG_KILL  = false # Ensure next call will not insta-stop
        # Close the SDR
        close(tup.csdr)
    end 
    return tup
end


function stop_runtime(tup)
    @info "Stopping all threads"
    OBS_Task[] = 0
    # SDR safe stop 
    @async Base.throwto(tup.task_producer,InterruptException())
    fetch(tup.task_producer)
    #sleep(1)
    # Task stop 
    @async Base.throwto(tup.task_consummer,InterruptException())
    @async Base.throwto(tup.task_rendering,InterruptException())
    # Destroy the GUI
    for cb in tup.list_cb
        # Remove all observables from GUI
        off(cb) 
    end
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

