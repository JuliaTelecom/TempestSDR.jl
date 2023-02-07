# ----------------------------------------------------
# --- Multi process environnement 
# ---------------------------------------------------- 
using TempestSDR

# ----------------------------------------------------
# --- Template signal for radiosim
# ---------------------------------------------------- 
try 
    if IS_LOADED == false 
        rethrow(InterruptException())
    end
catch exception 
    @info "Loading data"
    #local completePath = "$(pwd())/$DATA_PATH/testX310.dat"
    local completePath = "/Users/Robin/data_tempest/testX310.dat"
    global sigRx = readComplexBinary(completePath,:single)
    #global sigId = sigRx
    global DUMP = sigRx
    global IS_LOADED = true 
end



function start_runtime(device=:radiosim,renderer=:makie)
    # ----------------------------------------------------
    # --- SDR parameters 
    # ---------------------------------------------------- 
    carrierFreq  = 764e6
    samplingRate = 20e6
    gain         = 50 
    acquisition   = 0.70
    #nbS = Int( 80 * 99900)
    nbS = Int(round(acquisition * samplingRate))

    # ----------------------------------------------------
    # --- Remote SDR call 
    # ---------------------------------------------------- 

    # ----------------------------------------------------
    # --- Instantiate radio 
    # ---------------------------------------------------- 
    runtime = init_tempestSDR_runtime(device,carrierFreq,samplingRate,gain;addr="usb:1.4.5",bufferSize=nbS,buffer=sigRx,packetSize=nbS)
    # --- Start radio thread for IQ recv
    print(runtime.csdr.sdr)
    task_producer = Threads.@spawn start_thread_sdr(runtime.csdr)


    # ----------------------------------------------------
    # --- Start the renderer as the core processing
    # ---------------------------------------------------- 
    # --- Init the GUI 
    screen = initScreenRenderer(renderer,TempestSDR.CONFIG.height,TempestSDR.CONFIG.width)
    # --- Start the listeners 

    # ----------------------------------------------------
    # --- First extract autocorrelation properties 
    # ---------------------------------------------------- 
     r,g,r_yt,g_yt,fv,yt = extract_configuration(runtime)
     @show fv, yt
     plot_findRefresh(screen,r,g,fv)
     plot_findyt(screen,r_yt,g_yt,yt)

    # ----------------------------------------------------
    # --- Launching image generation 
    # ---------------------------------------------------- 
    @info "Launching tasks"
    # Rendering with @async to ensure this is on main thread 
    task_rendering  = @async image_rendering(screen)
    println(".")
    # Consommation in remote thread
    task_consummer  = Threads.@spawn coreProcessing(runtime)
    println(".")

    @info "Tasks spawned"
    sleep(1)
    return (;runtime,task_producer,task_consummer,task_rendering,screen)
end


function stop_runtime(tup)
    @info "Stopping all threads"
    # SDR safe stop 
    @async Base.throwto(tup.task_producer,InterruptException())
    sleep(1)
    # Task stop 
    @async Base.throwto(tup.task_consummer,InterruptException())
    @async Base.throwto(tup.task_rendering,InterruptException())
    # Safely close radio 
    close(tup.runtime.csdr)
    return nothing
end
