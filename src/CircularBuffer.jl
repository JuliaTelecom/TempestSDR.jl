module CircularBuffer 
using Base: PipeEndpoint
""" Module for managing data from the SDR with a circular buffer way. We will put all the received buffers in a circular buffer. With classic Julia Channels, `put!` will wait `pop`. In this proposed way the `push` will erase the oldest non poped data.
"""

# ----------------------------------------------------
# --- Dependencies 
# ---------------------------------------------------- 
using AbstractSDRs 
import Base:close 

# ----------------------------------------------------
# --- Structure 
# ---------------------------------------------------- 
mutable struct _CircularSDR_3{T}
    sdr::T
    buffer::Vector{ComplexF32}
    channel::Channel
    depth::Int                   # Number of channels in the circular buffer
    nbStored::Int                # Number of stored buffers 
    nbDropped::Int               # Number of dropped buffers 
    nbProcessed::Int               # Number of read buffers
end
CircularSDR = _CircularSDR_3



INTERRUPT::Bool = false

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
function configure_sdr(args...;depth = 5,bufferSize=1024,kw...)
    sdr = openSDR(args...;kw...)
    # --- Configure the circular buffer 
    buffer  = zeros(ComplexF32,bufferSize)
    channel  = Channel{Vector{ComplexF32}}(3)

    return CircularSDR(sdr,buffer,channel,depth,0,0,0)
end


function close(csdr::CircularSDR) 
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
            # --- Push on the channel 
            csdr.nbStored += circ_put!(csdr.channel,csdr.buffer)
            #print(".")
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


""" Put `data` in `channel`. If no space is available in the channel then remove oldest item.
"""
function circ_put!(channel::Channel,data)
    dropped = 0
    while(channel.n_avail_items >= channel.sz_max)
        take!(channel)
        dropped += 1
        yield()
    end 
    put!(channel,deepcopy(data)) 
    return dropped 
end

# ----------------------------------------------------
# --- Consummer 
# ---------------------------------------------------- 


"""" Get a buffer from the radio that uses a circular buffer. Performs an AM demodulation
"""
function circ_take!(csdr::CircularSDR)
    buff = take!(csdr.channel)
    #return abs2.(buff)
end


function circ_consummer(csdr) 
   cnt = 0 
    global INTERRUPT = false
    try 
        # While loop to have continunous streaming 
        while (!INTERRUPT)
            # --- Classic SDR call 
            buffer = circ_take!(csdr)            
            csdr.nbProcessed += 1
            cnt += 1
            yield()
            println(buffer[1])
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
