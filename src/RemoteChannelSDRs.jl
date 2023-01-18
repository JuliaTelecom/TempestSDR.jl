module RemoteChannelSDRs
""" Module for managing data from the SDR with a circular buffer way. We will put all the received buffers in a circular buffer. With classic Julia Channels, `put!` will wait `pop`. In this proposed way the `push` will erase the oldest non poped data.
"""

# ----------------------------------------------------
# --- Dependencies 
# ---------------------------------------------------- 
using AbstractSDRs 
import AbstractSDRs:AbstractSDR
import Base:close 
using Reexport 
using Distributed

# ----------------------------------------------------
# --- Exportation 
# ---------------------------------------------------- 
export RemoteChannelSDR
export configure_sdr 
export start_remote_sdr
export stop_remote_sdr
export circ_producer
export circ_consummer
export close 

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


# ----------------------------------------------------
# --- Structure 
# ---------------------------------------------------- 
mutable struct RemoteChannelSDR  # On PID 1 (SDR on PID 2)
    channel::RemoteChannel
    buffer::Vector{ComplexF32} 
    circ_buff::AtomicCircularBuffer 
    nbStored::Int 
    nbDropped::Int 
    nbProcessed::Int
end


# ----------------------------------------------------
# --- Manager
# ---------------------------------------------------- 
function stop_remote_sdr()
    global INTERRUPT_REMOTE = true 
end


""" Open and configure the SDR 
Configure also the circular buffer used for data managment 
"""
function configure_sdr(channel,bufferSize=1024)
    #sdr = openSDR(args...;kw...)
    # --- Configure the circular buffer 
    buffer  = zeros(ComplexF32,bufferSize)
    circ_buff = AtomicCircularBuffer{ComplexF32}(bufferSize,4)
    return RemoteChannelSDR(channel,buffer,circ_buff,0,0,0)
end


function close(csdr::RemoteChannelSDR) 
    AtomicCircularBuffers.atomic_stop(csdr.circ_buff)
    #close(csdr.sdr)
end

function start_remote_sdr(channel,buffsize,args...;kw...) # launched with @spawnat 2 start_remote_sdr(...)
    sdr = try openSDR(args...;kw...)
    catch exception 
        rethrow(exception)
    end
    print(sdr)
    cnt = 0 
    buffer = zeros(ComplexF32,buffsize)
    global INTERRUPT_REMOTE = false
    try 
        # While loop to have continunous streaming 
        while (INTERRUPT_REMOTE == false)
            # --- Classic SDR call 
            recv!(buffer,sdr)
            # Put in remote 
            #sleep(0.01) #FIXME for radiosim to avoid throttle 
            put!(channel,buffer) # Depth 1, will not block as circ_producer consummes it
            # 
            #(mod(cnt,10) == 0) && (println("$INTERRUPT_REMOTE"))
            yield()
            cnt += 1
        end
    catch exception 
        #rethrow(exception)
    end
    close(sdr)
    @info "Stopping remote producer call. Gathered $cnt buffers"
    return cnt,sdr
end

# ----------------------------------------------------
# --- Producer 
# ---------------------------------------------------- 
""" Apply the SDR procedure to fill the circular buffer in a given thread.
"""
function circ_producer(csdr::RemoteChannelSDR)
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
    @info "Stopping radio producer thread. Gathered $cnt buffers."
    return cnt
end


# ----------------------------------------------------
# --- Consummer 
# ---------------------------------------------------- 
function circ_consummer(csdr) 
    cnt = 0 
    buffer = similar(csdr.buffer)
    buffer_abs = zeros(Float32,length(buffer))
    local_stop = false
    global INTERRUPT = false
    try 
        # While loop to have continunous streaming 
        while (local_stop == false )
            # --- Classic SDR call 
            circ_take!(buffer,csdr.circ_buff)            
            # Abs
            buffer_abs .= abs2.(buffer)
            #
            csdr.nbProcessed += 1
            cnt += 1
            yield()
            # Wait to empty the circular buffer
            if INTERRUPT == true 
                if AtomicCircularBuffers.atomic_read(csdr.circ_buff.t_new) == 0
                    local_stop = true 
                end
            end
            #Main.infiltrate(@__MODULE__, Base.@locals, @__FILE__, @__LINE__)
            #(mod(cnt,100) && print("."))
        end
    catch exception 
        #rethrow(exception)
    end
    @info "Stopping radio consummer thread. Gathered $cnt buffers."
    return cnt
end


end
