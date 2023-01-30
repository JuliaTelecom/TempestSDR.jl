# ----------------------------------------------------
# --- Multi process environnement 
# ---------------------------------------------------- 
#include("../setMP.jl")
using TempestSDR



#@everywhere begin 
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
    # ----------------------------------------------------
    # --- Mode for runtime 
    # ---------------------------------------------------- 
#end


function start_runtime(duration,device=:radiosim)
    # ----------------------------------------------------
    # --- SDR parameters 
    # ---------------------------------------------------- 
    carrierFreq  = 764e6
    samplingRate = 8e6
    gain         = 50 
    acquisition   = 0.10
    #nbS = Int( 80 * 99900)
    nbS = Int(round(acquisition * samplingRate))

    # ----------------------------------------------------
    # --- Remote SDR call 
    # ---------------------------------------------------- 

    # ----------------------------------------------------
    # --- Instantiate radio 
    # ---------------------------------------------------- 
    if device == :radiosim 
        runtime = init_tempestSDR_runtime(:radiosim,carrierFreq,samplingRate,gain;addr="usb:1.4.5",bufferSize=nbS,buffer=sigRx,packetSize=nbS,renderer=:makie)
    else 
    runtime = init_tempestSDR_runtime(device,carrierFreq,samplingRate,gain,bufferSize=nbS,renderer=:makie;addr="usb:0.10.5")
    end
    # ----------------------------------------------------
    # --- Start radio threads 
    # ---------------------------------------------------- 
    print(runtime.csdr.sdr)
    task_producer = Threads.@spawn start_thread_sdr(runtime.csdr)
    # ----------------------------------------------------
    # --- First extract autocorrelation properties 
    # ---------------------------------------------------- 
    extract_configuration(runtime)

    runtime.config.refresh = 60.14

    screen = initScreenRenderer(runtime.renderer,runtime.config.height,runtime.config.width)

    # ----------------------------------------------------
    # --- Launching image generation 
    # ---------------------------------------------------- 
    # Rendering with @async to ensure this is on main thread 
    task_rendering  = @async image_rendering(runtime,screen)
    # Consommation in remote thread
    task_consummer  = Threads.@spawn coreProcessing(runtime)

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
