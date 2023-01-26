# ----------------------------------------------------
# --- Multi process environnement 
# ---------------------------------------------------- 
include("../setMP.jl")



@everywhere begin 
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
end


function start_runtime(duration;runtime_mode=:radiosim)
    # ----------------------------------------------------
    # --- SDR parameters 
    # ---------------------------------------------------- 
    carrierFreq  = 764e6
    samplingRate = 20e6
    gain         = 20 
    acquisition   = 1.00
    #nbS = Int( 80 * 99900)
    nbS = Int(round(acquisition * samplingRate))

    # ----------------------------------------------------
    # --- Remote SDR call 
    # ---------------------------------------------------- 

    # ----------------------------------------------------
    # --- Instantiate radio 
    # ---------------------------------------------------- 
    if runtime_mode == :radiosim 
        runtime = init_tempestSDR_runtime(:radiosim,carrierFreq,samplingRate,gain;addr="usb:1.4.5",bufferSize=nbS,buffer=sigRx,packetSize=nbS,renderer=:makie)
    else 
        runtime = init_tempestSDR_runtime(runtime_mode,carrierFreq,samplingRate,gain;addr="usb:0.10.5",bufferSize=nbS,renderer=:makie)
    end
    # ----------------------------------------------------
    # --- Start radio threads 
    # ---------------------------------------------------- 
    task_producer = start_remote_sdr(runtime.csdr)
    # ----------------------------------------------------
    # --- First extract autocorrelation properties 
    # ---------------------------------------------------- 
    extract_configuration(runtime)
    screen = initScreenRenderer(runtime.renderer,runtime.config.height,runtime.config.width)

    # ----------------------------------------------------
    # --- Launching image generation 
    # ---------------------------------------------------- 
    # Rendering with @async to ensure this is on main thread 
    task_rendering  = @async image_rendering(runtime,screen)
    # Consommation in remote thread
    task_consummer  = Threads.@spawn coreProcessing(runtime)


    # ----------------------------------------------------
    # --- Stopping threads
    # ---------------------------------------------------- 
    sleep(duration) 

    @info "Stopping all threads"
    # SDR safe stop 
    stop_remote_sdr() 
    sleep(1)
    # Task stop (rather hard here :D)
    @async Base.throwto(task_consummer,InterruptException())
    @async Base.throwto(task_rendering,InterruptException())

    #stop_runtime(runtime)
    return (;runtime,task_producer,task_consummer,task_rendering,screen)
end
