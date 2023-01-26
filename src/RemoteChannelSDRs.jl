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

# ----------------------------------------------------
# --- Exportation 
# ---------------------------------------------------- 
export MultiThreadSDR
export open_thread_sdr
export start_thread_sdr
export stop_thread_sdr
export recv!
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


mutable struct MultiThreadSDR 
    sdr::AbstractSDR
    buffer::Vector{ComplexF32} 
    circ_buff::AtomicCircularBuffer 
    nbStored::Int 
    nbDropped::Int 
    nbProcessed::Int

end

# ----------------------------------------------------
# --- Manager
# ---------------------------------------------------- 

""" Open a remote SDR system. It consists with an SDR on a specific Core (with no others processing tasks and a circular buffer managment on the processing core 
"""
function open_thread_sdr(args...;bufferSize=1024,kw...)
    sdr = openSDR(args...;kw...) 
    buffer  = zeros(ComplexF32,bufferSize)
    circ_buff = AtomicCircularBuffer{ComplexF32}(bufferSize,4)
    return MultiThreadSDR(sdr,buffer,circ_buff,0,0,0)
end


function start_thread_sdr(csdr::MultiThreadSDR)
    cnt = 0 
    global INTERRUPT = false
    try 
        # While loop to have continunous streaming 
        while (!INTERRUPT)
            # --- Classic SDR call 
            recv!(csdr.buffer,csdr.sdr)
            # --- Push on the atomic circular buffer
            circ_put!(csdr.circ_buff,csdr.buffer)
            csdr.nbStored += 1
            cnt += 1
        end
    catch exception 
        #rethrow(exception)
    end
    @info "Stopping local radio producer thread. Gathered $cnt buffers."
    return cnt
end
function stop_thread_sdr() 
    global INTERRUPT = true 
end

function recv!(buffer,csdr::MultiThreadSDR)
    circ_take!(buffer,csdr.circ_buff)
end

end
