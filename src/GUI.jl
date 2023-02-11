using AbstractSDRs
using Makie, GLMakie 
using Base.Threads
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
# Start // Stop 
#OBS_running = Observable{Bool}(false)
OBS_running = Observable{Bool}(false)
# Flags 
FLAG_CONFIG_UPDATE::Bool = false 
# Video Config
VIDEO_CONFIG::VideoMode = VideoMode(1024,768,60) 
rates_refresh::Vector{Float32} = []
Γ_refresh::Vector{Float32} = []
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
    global FLAG_CONFIG_UPDATE,RENDERING_SIZE 
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
            if FLAG_CONFIG_UPDATE == true 
                image_size_down = getImageDuration(VIDEO_CONFIG,samplingRate_real)
                nbIm = length(csdr.buffer) ÷ image_size_down   # Number of image at SDR rate 
                FLAG_CONFIG_UPDATE = false 
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
            # Get a new image 
            imageOut .= take!(channelImage)::Matrix{Float32}
            imageOut .= ScreenRenderer.fullScale!(imageOut)
            cnt += 1
            #displayScreen!(plot_obj,imageOut)
            gui.heatmap[1] = collect(imageOut') 
            #gui.figure.content[1] = image(imageOut)
            #empty!(gui.fig.content[1])
            #image!(gui.fig.content[1],collect(imageOut'))
            #gui.fig.content[1].scene[1][1] = collect(imageOut')
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

# ----------------------------------------------------
# --- GUI 
# ---------------------------------------------------- 
function initGUI()
    # --- Define the Grid Layout 
    figure = Figure(backgroundcolor=:lightgrey,resolution=(1800,1200))
    g_im = figure[1:6, 1:3] = GridLayout()
    g_T = figure[7, 1:4] = GridLayout()
    g_Z = figure[8, 1:4] = GridLayout()
    infoPanel = figure[1,4]
    # --- Add a first image
    axIm = Makie.Axis(g_im[1,1])
    m = randn(Float32,RENDERING_SIZE...)
    plot_obj = ScreenRenderer._plotHeatmap(axIm,m)
    #plot_obj = image(m)
    axIm.yreversed = true
    # --- Display the first lines for correlation 
    axT = Makie.Axis(g_T[1,1])
    delay = 1 : 100
    corr = zeros(Float32,100)
    ScreenRenderer._plotInteractiveCorrelation(axT,delay,corr,0.0,:turquoise4)
    # The zoomed correlation 
    axZ = Makie.Axis(g_Z[1,1])
    ScreenRenderer._plotInteractiveCorrelation(axZ,delay,corr,0.0,:gold4)
    # The information panel 
    gc = infoPanel[1,1]
#    figure[1, 3] = buttongrid = GridLayout(tellwidth = false)
    btn = Button(gc, label = "RUN MODE", fontsize=35)
    #buttongrid[1, 1:1] = [btn]

    l_fv = Label(infoPanel[2,1], "Refresh Rate",tellwidth = false,fontsize=24)
    box_fv = Textbox(infoPanel[2,2], placeholder = "Refresh Rate",validator = Float64, tellwidth = false,fontsize=24)
    l_yt = Label(infoPanel[3,1], "Height size",tellwidth = false,fontsize=24)
    box_yt = Textbox(infoPanel[3,2], placeholder = "yt",validator = Int64, tellwidth = false,fontsize=24)


    infoPanel[3, 3] = buttongrid = GridLayout(tellwidth = false)
    btn = Button(buttongrid[1,1], label = "+", tellwidth = false,fontsize=14)
    btn = Button(buttongrid[2,1], label = "-", tellwidth = false,fontsize=16)
    rowgap!(buttongrid,0.15)
    # axtop = Makie.Axis(g_P[1, 1])
    #axbott = Makie.Axis(g_P[2:4, 1])
    #tb = Textbox(axtop.scene, placeholder = "yt ", validator = Int64, tellwidth = false)
    # Display the image 
    display(figure)
    # Final constructor
    return GUI(figure,plot_obj)
end
# ----------------------------------------------------
# --- Launch Figure
# ---------------------------------------------------- 

#task_producer = Threads.@spawn start_thread_sdr(csdr)


function listener_refresh(fig)
    global FLAG_CONFIG_UPDATE, OBS_fv
    ax  = fig.content[2]  # Axis for correlation  
    t   = ax.scene[2]     # Second index is the text 
    vL  = ax.scene[3]     # Third index is the vline 
    # Interactions on Refresh plane 
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
                OBS_fv[] = select_f
            end
        end
    end
end

function listener_yt(fig)
    global  FLAG_CONFIG_UPDATE, OBS_fv
    # ----------------------------------------------------
    # --- Find scene with correlation 
    # ---------------------------------------------------- 
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
                fv = OBS_fv[]
                y_t = delay2yt(select_y,fv)
                t[1] = " $(y_t)"
                # Config will be changed 
                FLAG_CONFIG_UPDATE = true
                # Fill the observable 
                OBS_yt[] = y_t
                #theConfig = find_closest_configuration(y_t,fv) |> dict2video
                ## Keep the rate as we have chosen 
                #theConfig.refresh = fv
                #theConfig.height= y_t
            end
        end
    end
end


function toggle_running()
    OBS_running[] = !OBS_running[] # or more complex logic
    if OBS_running[] == false 
        OBS_Task[] = 0
    else 
        OBS_Task[] = 1
    end
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


""" Add the correlation plot to the Makie figure 
"""
function plot_findRefresh(fig,rates,Γ,fv=0.0) 
    axis = fig.content[2]  
    ScreenRenderer._plotInteractiveCorrelation(axis,rates,Γ,fv,:gold2) 
    listener_refresh(fig)
    #lines!(ax,rates,Γ)
end

function plot_findyt(fig,rates,Γ,fv=0.0) 
    axis = fig.content[3]  
    ScreenRenderer._plotInteractiveCorrelation(axis,rates,Γ,fv,:turquoise4) 
    listener_yt(fig)
    #lines!(ax,rates,Γ)
end
# ----------------------------------------------------
# --- Listener on obs 
# ---------------------------------------------------- 
function start_runtime()
    # ----------------------------------------------------
    # --- Configuration 
    # ---------------------------------------------------- 
    global FLAG_CONFIG_UPDATE, VIDEO_CONFIG
    global rates_refresh, Γ_refresh
    # GUI 
    gui = initGUI()
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
    global task_producer = Threads.@spawn start_thread_sdr(csdr)

    global task_consummer  = Threads.@spawn coreProcessing(csdr)

    task_rendering  = @async image_rendering(gui)


    # ----------------------------------------------------
    # --- GUI definition 
    # ---------------------------------------------------- 
    btnStart = gui.fig.content[4]
    boxRefresh  = gui.fig.content[6]
    boxYt       = gui.fig.content[8]
    btnYt_plus  = gui.fig.content[9]
    btnYt_minus = gui.fig.content[10]
    plot_image  = gui.fig.content[1]
    plot_refresh= gui.fig.content[2]
    plot_yt     = gui.fig.content[3]


    # ----------------------------------------------------
    # --- Observables 
    # ---------------------------------------------------- 
    # List of observables, to be turned on in destruction 
    list_cb = []
    """ If we change the rate in the input box 
    -> Change the rate of observable 
    -> Redraw the correlation with line at proper place 
    """
    cb_box_fv = on(boxRefresh.stored_string) do fv 
        # 
        rr = parse(Float64, fv)
        OBS_fv[] = rr 
        OBS_Corr[] = true
    end
    push!(list_cb,cb_box_fv)


    """ If we change the height in the box 
    -> Change the value of the configuration 
    -> Change the location of the line in the zoom plot 
    """
    cb_box_yt = on(boxYt.stored_string) do yt 
        # 
        Fs = OBS_Fs[]::Float64
        rr = parse(Float64, yt)
        OBS_yt[] = rr 
        #OBS_Corr[] = true
        fv = OBS_fv[] 
        vv = yt2index(OBS_yt[],Fs,fv)
        plot_refresh.scene[3][1] = vv # FIXME 
#        N = 1000
        #posMax = argmin(abs.(rates_refresh .- fv))
        #Γ_yt = Γ_refresh[posMax .+ (1:N)]
        #r = range(0,step=1/Fs,length=N)
        #plot_findyt(gui.fig,r,Γ_yt,1/(fv*rr)) 
    end
    push!(list_cb,cb_box_yt)

    """ If we click on + or - in the boxes, it updates yt 
    -> Force trigger to ensure correlation redrawn
    """ 
    cb_click_plus = on(btnYt_plus.clicks) do clk 
        OBS_yt[] = OBS_yt[] + 1 
        boxYt.stored_string = string(OBS_yt[])
        OBS_yt[], OBS_fv[]
        pos = yt2delay(OBS_yt[],OBS_fv[])
        y_y = OBS_yt[]
        plot_yt.scene[3][1] = pos
        plot_yt.scene[2][1] = string(y_y)
        
    end
    push!(list_cb,cb_click_plus)
    cb_click_minus = on(btnYt_minus.clicks) do clk 
        OBS_yt[] = OBS_yt[] - 1 
        boxYt.stored_string = string(OBS_yt[])
        y_t = yt2delay(OBS_yt[],OBS_fv[])
        y_y = OBS_yt[]
        plot_yt.scene[3][1] = y_t # FIXME 
        plot_yt.scene[2][1] = string(y_y)
    end
    push!(list_cb,cb_click_minus)

    """ Interactive use of correlation to find refresh rate 
    -> Change the configuration 
    -> Change the value of fv in the text box 
    -> Change line position based on cursor 
    -> Change the zoom correlation panel 
    """
    #cb_events_refresh = on(events(plot_refresh.scene).mousebutton) do mp
        #@show plot_refresh
        #@show gui.fig.content
        #@show gui.fig.content[2]
        ##t  = plot_refresh.scene[2]
        #t  = gui.fig.content[2].scene[2]
        #vL = plot_refresh.scene[3]
        #if mp.button == Mouse.left
            #if is_mouseinside(plot_refresh.scene)
                #select_f,amp = mouseposition(plot_refresh.scene)
                ## Adding the annotation on the plot 
                #t.position = (select_f,amp)
                #t[1] = " $select_f"
                #t.visible = true
                ## Print a vertical line at this location 
                #vL[1] = select_f # FIXME Why int ?
                ## Update configuration
                #FLAG_CONFIG_UPDATE = true
                #OBS_fv[] = select_f
            #end
        #end
    #end
    #push!(list_cb,cb_events_refresh)
    cb_fv = on(OBS_fv) do fv 
        posMax = argmin(abs.(rates_refresh .- fv))
        fv = round(fv;digits=2)
        Fs = OBS_Fs[]::Float64
        # Update the config 
        FLAG_CONFIG_UPDATE = true 
        VIDEO_CONFIG.refresh = fv
        boxRefresh.stored_string.val = string(fv) # Update panel w/o launch cb
        boxRefresh.displayed_string= string(fv) # Update panel w/o launch cb
       # Update the line panel 
        N = 1000
        Γ_yt = Γ_refresh[posMax .+ (1:N)]
        r = range(0,step=1/OBS_Fs[],length=N)
        y_t = delay2yt(OBS_yt[],fv)
         plot_findyt(gui.fig,r,Γ_yt,y_t) 

    end
    push!(list_cb,cb_fv)

    """ Interactive use of zoom correlation for yt 
    -> Change the configuration (based on closer config)
    -> Change line position based on cursor  
    -> Change the value in the text box 
    """
#    cb_events_yt = on(events(plot_yt.scene).mousebutton) do mp
        #@show plot_yt
        #t  = plot_yt.scene[2]
        #vL = plot_yt.scene[3]
        #if mp.button == Mouse.left
            #select_y,amp = mouseposition(plot_yt.scene)
            #t.position = (select_y,amp)
            #t.visible = true
            #vL[1] = select_y
            ## Print a vertical line at this location 
            ##vL[1] = round(select_f) # FIXME Why int ?
            ## Change selection of f to a number of lines 
            #fv = OBS_fv[]
            #y_t = delay2yt(select_y,fv)
            #t[1] = " $(y_t)"
            ## Config will be changed 
            #FLAG_CONFIG_UPDATE = true
            ## Fill the observable 
            #OBS_yt[] = y_t 
        #end
    #end
    #push!(list_cb,cb_events_yt)

    cb_yt = on(OBS_yt) do yt 
        FLAG_CONFIG_UPDATE = true 
        theConfig = find_closest_configuration(yt,OBS_fv[]) |> dict2video
        # Keep the rate as we have chosen 
        VIDEO_CONFIG.height= yt
        VIDEO_CONFIG.width = theConfig.width
        boxYt.displayed_string= string(yt) # Update panel w/o laucnh cb

    end
    push!(list_cb,cb_yt)

    """ Observable that states correlation should be redrawn 
    -> Redrawthe correlation (for fv) plot 
    """
    cb_corr = on(OBS_Corr) do new_corr
        if new_corr == true 
            plot_findRefresh(gui.fig,rates_refresh,Γ_refresh,OBS_fv[])
            OBS_Corr[] = false 
        end 
    end
    push!(list_cb,cb_corr)

    """ RUN mode : toggle the mode 
    -> Start the correlation task 
    -> Or Stop the processing task 
    """
    cb_click = on(btnStart.clicks) do clk 
        toggle_running() 
        if OBS_running[] == true 
            gui.fig.content[4].label = "PAUSE" 
            OBS_Task[] = 1
        else 
            gui.fig.content[4].label = "RUN !"
            OBS_Task[] = 0
        end
    end
    push!(list_cb,cb_click)

    """ Task mode 
    -> 1 : Correlation and auto config 
    -> 2 : Processing mode for image rendering 
    """
    cb_task = on(OBS_Task) do task 
        if task == 1 
            # ----------------------------------------------------
            # --- Configuration task 
            # ---------------------------------------------------- 
            rates_refresh,Γ_refresh,fv = extract_configuration(csdr)
            OBS_fv[] = fv
            OBS_Corr[] = true
            OBS_Task[] = 2
        elseif task == 2 
            # ----------------------------------------------------
            # --- Image processing task 
            # ---------------------------------------------------- 
            @info "Processing NOW !!!"
        end
    end
    push!(list_cb,cb_task)

    return (;gui, list_cb,csdr, task_producer, task_consummer, task_rendering) 
    #return (;fig, csdr, task_producer, task_consummer) 
end



function stop_runtime(tup)
    @info "Stopping all threads"
    OBS_Task[] = 0
    # SDR safe stop 
    @async Base.throwto(tup.task_producer,InterruptException())
    sleep(1)
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
    destroy(tup.gui)
    return nothing
end


function destroy(gui::GUI)
    sc = GLMakie.Makie.getscreen(gui.fig.scene)
    if !isnothing(sc)
        GLMakie.destroy!(sc)
    end 
end
