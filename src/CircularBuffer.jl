module CircularBuffer 
using Base: PipeEndpoint
""" Module for managing data from the SDR with a circular buffer way. We will put all the received buffers in a circular buffer. With classic Julia Channels, `put!` will wait `pop`. In this proposed way the `push` will erase the oldest non poped data.
"""

# ----------------------------------------------------
# --- Dependencies 
# ---------------------------------------------------- 
using AbstractSDRs 
import AbstractSDRs:AbstractSDR
import Base:close 
using Reexport 


# ----------------------------------------------------
# --- Exportation 
# ---------------------------------------------------- 
export CircularSDR
export configure_sdr 
export circ_producer
export circ_consummer
export circ_stop
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


# ----------------------------------------------------
# --- Structure 
# ---------------------------------------------------- 
mutable struct CircularSDR 
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
""" Stop the `circular_sdr_start` procedure.
"""
function circ_stop(csdr)
    global INTERRUPT = true 
    close(csdr)
end


""" Open and configure the SDR 
Configure also the circular buffer used for data managment 
"""
function configure_sdr(args...;bufferSize=1024,kw...)
    sdr = openSDR(args...;kw...)
    # --- Configure the circular buffer 
    buffer  = zeros(ComplexF32,bufferSize)
    circ_buff = AtomicCircularBuffer(bufferSize)

    return CircularSDR(sdr,buffer,circ_buff,0,0,0)
end


function close(csdr::CircularSDR) 
    AtomicCircularBuffers.atomic_stop(csdr.circ_buff)
    close(csdr.sdr)
end



# ----------------------------------------------------
# --- Producer 
# ---------------------------------------------------- 
""" Apply the SDR procedure to fill the circular buffer in a given thread.
"""
function circ_producer(csdr::CircularSDR)
    cnt = 0 
    global INTERRUPT = false
    try 
        # While loop to have continunous streaming 
        while (!INTERRUPT)
            # --- Classic SDR call 
            recv!(csdr.buffer,csdr.sdr)
            yield()
            # --- Push on the atomic circular buffer
            circ_put!(csdr.circ_buff,csdr.buffer)
            csdr.nbStored += 1
            cnt += 1
            #(mod(cnt,100) && print("."))
        end
    catch exception 
        rethrow(exception)
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
            #println(buffer[1])
            #Main.infiltrate(@__MODULE__, Base.@locals, @__FILE__, @__LINE__)
            #(mod(cnt,100) && print("."))
        end
    catch exception 
        rethrow(exception)
    end
    @info "Stopping radio consummer thread. Gathered $cnt buffers."
    return cnt
end


end
