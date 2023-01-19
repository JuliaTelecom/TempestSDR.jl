# ----------------------------------------------------
# --- Multi process environnement 
# ---------------------------------------------------- 
include("../setMP.jl")


# ----------------------------------------------------
# --- Core processing arguments 
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
#PID_SDR = TempestSDR.PID_SDR



function start_runtime(duration)
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
    runtime = init_tempestSDR_runtime(:pluto,carrierFreq,samplingRate,gain;addr="usb:1.4.5",bufferSize=nbS,renderer=:makie)
    # ----------------------------------------------------
    # --- Start radio threads 
    # ---------------------------------------------------- 
    task_producer = start_remote_sdr(runtime.csdr)
    # ----------------------------------------------------
    # --- First extract autocorrelation properties 
    # ---------------------------------------------------- 
    extract_configuration(runtime)
    # ----------------------------------------------------
    # --- Launching image generation 
    # ---------------------------------------------------- 
    task_rendering  = @async image_rendering(runtime)
    task_consummer  = @async coreProcessing(runtime)


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
    return (;runtime,task_producer,task_consummer,task_rendering)
end
