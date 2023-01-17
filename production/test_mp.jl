# ----------------------------------------------------
# --- Multi process environnement 
# ---------------------------------------------------- 
include("../setMP.jl")

@everywhere begin 
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
PID_SDR = TempestSDR.PID_SDR



function start_runtime(duration)
    # ----------------------------------------------------
    # --- SDR parameters 
    # ---------------------------------------------------- 
    carrierFreq  = 764e6
    samplingRate = 8e6
    gain         = 20 
    acquisition   = 0.05
    nbS = Int( 80 * 99900)

    # ----------------------------------------------------
    # --- Remote SDR call 
    # ---------------------------------------------------- 
    global channel = RemoteChannel(()->Channel{Vector{ComplexF32}}(1), PID_SDR)
    future_prod = @spawnat PID_SDR start_remote_sdr(channel,nbS,:radiosim,carrierFreq,buffer=sigRx,bufferSize=nbS,samplingRate,gain;depth=4,addr="usb:0.4.5",packetSize=nbS)


    # ----------------------------------------------------
    # --- Instantiate radio 
    # ---------------------------------------------------- 
    runtime = init_tempestSDR_runtime(channel,nbS,:makie)
    # ----------------------------------------------------
    # --- Start radio thread 
    # ---------------------------------------------------- 
    task_producer = @async circ_producer(runtime.csdr) 

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
    run(`clear`)
    @info "Stopping all threads"
    # Stopping SDR call 
    remote_do(stop_remote_sdr,PID_SDR)
    sleep(0.1)
    # Stopping other calls
    stop_processing()

    return (;runtime,task_producer,task_consummer,task_rendering,future_prod)
end
