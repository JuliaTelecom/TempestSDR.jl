
# ----------------------------------------------------
# --- Multi process environnement 
# ---------------------------------------------------- 
include("../setMP.jl")

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
# --- Init runtime 
# ---------------------------------------------------- 
function start_runtime()
    # ----------------------------------------------------
    # --- SDR parameters 
    # ---------------------------------------------------- 
    carrierFreq  = 764e6
    samplingRate = 8e6
    gain         = 20 
    acquisition   = 0.5 
    # ----------------------------------------------------
    # --- Instantiate radio 
    # ---------------------------------------------------- 
    nbS = Int( samplingRate * acquisition)
    global runtime = init_tempestSDR_runtime(:pluto,carrierFreq,samplingRate,gain;addr="usb:0.4.5",depth=4,buffer=sigRx,bufferSize=nbS,packetSize=nbS,renderer=:makie)
    # ----------------------------------------------------
    # --- Start radio thread 
    # ---------------------------------------------------- 
    task_producer = @async circ_producer(runtime.csdr) 
    # ----------------------------------------------------
    # --- First extract autocorrelation properties 
    # ---------------------------------------------------- 
    #extract_configuration(runtime)
    # ----------------------------------------------------
    # --- Launching image generation 
    # ---------------------------------------------------- 
    #task_rendering  = @async image_rendering(runtime)
    #task_consummer  = @async coreProcessing(runtime)
    # ----------------------------------------------------
    # --- Image rendering 
    # ---------------------------------------------------- 
    #try 
    #image_rendering(runtime)
    #catch exception 
    #@info "Interruption" 
    #println(exception)
    #end
    #return (;runtime,task_producer,task_consummer,task_rendering)
    return (;runtime,task_producer)
end

# ----------------------------------------------------
# --- Stopping runtime 
# ---------------------------------------------------- 
#(runtime, task_producer,task_consummer,task_rendering) = start_runtime()
tup = start_runtime()
sleep(20)
stop_processing(tup.runtime)
