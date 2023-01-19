module RemoteChannelSDRs
""" Module for managing data from the SDR with a circular buffer way. We will put all the received buffers in a circular buffer. With classic Julia Channels, `put!` will wait `pop`. In this proposed way the `push` will erase the oldest non poped data.
"""

# ----------------------------------------------------
# --- Dependencies 
# ---------------------------------------------------- 
using AbstractSDRs 
import AbstractSDRs:AbstractSDR
import Base:close 
import AbstractSDRs:recv!
using Reexport 
using Distributed

# ----------------------------------------------------
# --- Exportation 
# ---------------------------------------------------- 
export LocalProcessSDR
export DistantProcessSDR
export open_remote_sdr
export start_remote_sdr
export stop_remote_sdr
export recv!
export close 
export @remote_sdr

# ----------------------------------------------------
# --- Atomic circular buffers 
# ---------------------------------------------------- 
include("AtomicCircularBuffers.jl")
@reexport using .AtomicCircularBuffers


# ----------------------------------------------------
# --- Global variables 
# ---------------------------------------------------- 
INTERRUPT::Bool = false
INTERRUPT_REMOTE::Bool = false
import ..TempestSDR: PID_SDR

global channel = RemoteChannel(()->Channel{Vector{ComplexF32}}(1))
# ----------------------------------------------------
# --- Structure 
# ---------------------------------------------------- 
"""" Structure for local mirror of the SDR (typically on proc 1)
"""
mutable struct LocalProcessSDR  # On PID 1 (SDR on PID 2)
    channel::RemoteChannel
    buffer::Vector{ComplexF32} 
    circ_buff::AtomicCircularBuffer 
    nbStored::Int 
    nbDropped::Int 
    nbProcessed::Int
end

""" Structure for distant SDR process (typically on proc 2)
""" 
mutable struct DistantProcessSDR
    pid::Int 
    sdr::AbstractSDR 
    bufferSize::Int
    function DistantProcessSDR(args...;bufferSize=1024,kw...)
        sdr = openSDR(args...;kw...)
        pid = PID_SDR
        global distantSDR = new(pid,sdr,bufferSize)
        return distantSDR
    end
end


""" This macro allow to communicate with the remote SDR on the other procs. It assumes that only one SDR is present at set as a global variable 
To launch a command associated to the remote SDR use the same API as abstractSDRs and replace the SDR parameter with _ 
For example to update the carrier frequency of the SDR to 2400MHz, with AbstractSDSRs it will be 
updateCarrierFreq!(sdr,2400e6) 
With the remote SDR the macro call will be 
@remote_sdr updateCarrierFreq!(_,2400e6) 
All the functionnality of the SDR can be pass with this macro. For example, to obtain SDR parameter through AbstractSDRs accessor, one can use 
samplingRate = @remote_sdr getSamplingRate(_)
"""
macro remote_sdr(ex) 
    # SDR location at core 2 
    sdrLoc = "TempestSDR.RemoteChannelSDRs.distantSDR" 
    #sdrLoc = "distantSDR" 
    str = string(ex)
    rr = "using TempestSDR, AbstractSDRs;"*replace(str, "_" => sdrLoc)
    quote 
        fetch(@spawnat PID_SDR eval(Meta.parse($rr)))
    end
end

# ----------------------------------------------------
# --- Manager
# ---------------------------------------------------- 

""" Open a remote SDR system. It consists with an SDR on a specific Core (with no others processing tasks and a circular buffer managment on the processing core 
"""
function open_remote_sdr(args...;bufferSize=1024,kw...)
    global channel
    # ----------------------------------------------------
    # --- [DistantProcessSDR] Managing Radio on PID_SDR core 
    # ---------------------------------------------------- 
    # Call to init 
    future = @spawnat PID_SDR DistantProcessSDR(args...;kw...,bufferSize)
    res = fetch(future)
    # Define global variable located at PID_SDR
    #task_instantiate = @spawnat PID_SDR eval(:(distantSDR = TempestSDR.RemoteChannelSDRs.distantSDR))
    #@show fetch(task_instantiate)   
    # ----------------------------------------------------
    # --- [LocalProcessSDR] Managing CircularBuffer on local core 
    # ---------------------------------------------------- 
    buffer  = zeros(ComplexF32,bufferSize)
    circ_buff = AtomicCircularBuffer{ComplexF32}(bufferSize,4)
    return LocalProcessSDR(channel,buffer,circ_buff,0,0,0)
end



function start_remote_sdr(csdr::LocalProcessSDR)
    # ----------------------------------------------------
    # --- [Distant] Launch distant process 
    # ---------------------------------------------------- 
    global future  = @spawnat PID_SDR start_distant_sdr()
    # ----------------------------------------------------
    # --- [Remote] Launch remote SDR 
    # ---------------------------------------------------- 
    task_producer = @async start_local_sdr(csdr) 
    return task_producer 
end

    
function stop_remote_sdr()
    # ----------------------------------------------------
    # --- [Distant] Stop Distant process 
    # ---------------------------------------------------- 
    fetch(remote_do(stop_distant_sdr,PID_SDR))
    # ----------------------------------------------------
    # --- [Remote] Stop local process 
    # ---------------------------------------------------- 
    stop_local_sdr()
end

function close(csdr::LocalProcessSDR) 
    # --- Stop the DistantProcessSDR 
    #@remote_sdr close(_)
    # --- Stop the LocalProcessSDR 
    AtomicCircularBuffers.atomic_stop(csdr.circ_buff)
    #close(csdr.sdr)
end




# ----------------------------------------------------
# --- Distant tasks 
# ---------------------------------------------------- 
function start_distant_sdr() # launched with @spawnat 2 start_distant_sdr()
    global distantSDR
    global channel
    cnt = 0 
    buffer = zeros(ComplexF32,distantSDR.bufferSize)
    global INTERRUPT_REMOTE = false
    try 
        # While loop to have continunous streaming 
        while (INTERRUPT_REMOTE == false)
            # --- Classic SDR call 
            recv!(buffer,distantSDR.sdr)
            # Put in remote 
            #sleep(0.01) #FIXME for radiosim to avoid throttle 
            put!(channel,buffer) # Depth 1, will not block as circ_producer consummes it
            # 
            #(mod(cnt,10) == 0) && (println("$INTERRUPT_REMOTE"))
            yield()
            cnt += 1
        end
    catch exception 
        rethrow(exception)
    end
    close(distantSDR.sdr)
    @info "Stopping remote producer call. Gathered $cnt buffers"
    return cnt
end

function stop_distant_sdr()
    global INTERRUPT_REMOTE = true 
end



# ----------------------------------------------------
# ---  Local tasks
# ---------------------------------------------------- 
""" Apply the SDR procedure to fill the circular buffer in a given thread.
"""
function start_local_sdr(csdr::LocalProcessSDR)
    cnt = 0 
    global INTERRUPT = false
    try 
        # While loop to have continunous streaming 
        while (!INTERRUPT)
            # --- Classic SDR call 
            # RemoteChannel call 
            while (!isready(csdr.channel)) 
                yield()
            end
            buffer = take!(csdr.channel)
            # --- Push on the atomic circular buffer
            circ_put!(csdr.circ_buff,buffer)
            csdr.nbStored += 1
            cnt += 1
        end
    catch exception 
        #rethrow(exception)
    end
    @info "Stopping local radio producer thread. Gathered $cnt buffers."
    return cnt
end


function stop_local_sdr() 
    global INTERRUPT = true 
end


function recv!(buffer,csdr::LocalProcessSDR)
    circ_take!(buffer,csdr.circ_buff)
end


end
