module CircularBuffer 
using Base: PipeEndpoint
""" Module for managing data from the SDR with a circular buffer way. We will put all the received buffers in a circular buffer. With classic Julia Channels, `put!` will wait `pop`. In this proposed way the `push` will erase the oldest non poped data.
"""

# ----------------------------------------------------
# --- Dependencies 
# ---------------------------------------------------- 
using AbstractSDRs 
using Sockets
import Base:close 

# ----------------------------------------------------
# --- Structure 
# ---------------------------------------------------- 
mutable struct _CircularSDR_3{T}
    sdr::T
    buffer::Vector{ComplexF32}
    socket::Sockets.TCPServer
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
export circular_sdr_start 
export circular_sdr_stop
export circular_sdr_take
export circular_put!
export close 

""" Open and configure the SDR 
Configure also the circular buffer used for data managment 
"""
function configure_sdr(args...;depth = 5,bufferSize=1024,kw...)
    sdr = openSDR(args...;kw...)
    # --- Configure the circular buffer 
    buffer  = zeros(ComplexF32,bufferSize)
    socket  = listen(42001)

    return CircularSDR(sdr,buffer,socket,depth,0,0,0)
end


function close(csdr::CircularSDR) 
    close(csdr.socket)
    close(csdr.sdr)
end


""" Apply the SDR procedure to fill the circular buffer in a given thread.
"""
function circular_sdr_start(csdr::CircularSDR)
    cnt = 0 
    global INTERRUPT = false
    conn = accept(csdr.socket)
    try 
        # While loop to have continunous streaming 
        while (!INTERRUPT)
            # --- Classic SDR call 
            recv!(csdr.buffer,csdr.sdr)
            yield()
            # --- Push on the channel 
            #csdr.nbStored += circular_put!(csdr.channel,csdr.buffer)
            write(conn,csdr.buffer)
            print(".")
            csdr.nbStored += 1
            cnt += 1
            #(mod(cnt,100) && print("."))
        end
    catch exception 
        rethrow(exception)
    end
    @info "Stopping radio thread. Gathered $cnt buffers."
    return cnt
end


""" Stop the `circular_sdr_start` procedure.
"""
function circular_sdr_stop(csdr)
    global INTERRUPT = true 
    close(csdr)
end

"""" Get a buffer from the radio that uses a circular buffer. Performs an AM demodulation
"""
function circular_sdr_take(csdr::CircularSDR)
    buff = read(csdr.socket)
    csdr.nbProcessed += 1
    return abs2.(buff)
    #return abs2.(take!(csdr.channel))
end

""" Put `data` in `channel`. If no space is available in the channel then remove oldest item.
"""
function circular_put!(channel::Channel,data)
    dropped = 0
    while(channel.n_avail_items >= channel.sz_max)
        take!(channel)
        dropped += 1
        yield()
    end 
    put!(channel,data) 
    return dropped 
end



end
