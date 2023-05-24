module AtomicAbstractSDRs
""" Module for managing data from the SDR with a circular buffer way from a distant thread
"""

# ----------------------------------------------------
# --- Dependencies 
# ---------------------------------------------------- 
using AbstractSDRs 
import AbstractSDRs:AbstractSDR
import Base:close 
import AbstractSDRs:recv!

# ----------------------------------------------------
# --- Exportation 
# ---------------------------------------------------- 
export AtomicAbstractSDR
export openAtomicSDR
export start_atomic_sdr
export stop_atomic_sdr
export recv!
export close 
export print_summary

# ----------------------------------------------------
# --- Circular Buffer internal module 
# ---------------------------------------------------- 
# This module provides thread safe circular buffer use toi put and take data 
module AtomicCircularBuffers
# ----------------------------------------------------
# --- Dependencies 
# ---------------------------------------------------- 
using Base.Threads 
# ----------------------------------------------------
# --- Exportation 
# ---------------------------------------------------- 
export AtomicCircularBuffer 
export circ_take! 
export circ_put!
# ----------------------------------------------------
# --- Structure 
# ---------------------------------------------------- 
""" Structure for Atomic (i.e Thread safe) buffer managment 
The buffer will be written using `atomic_write` and read using `atomic_read`
"""
mutable struct AtomicBuffer{T}
    lock::Vector{ReentrantLock}
    buffer::Vector{T} ## Only store flat array
    nEch::Int 
    depth::Int
    function AtomicBuffer{T}(nEch::Int,depth::Int) where T
        lock   = [ReentrantLock() for _ ∈ 1 : depth]
        buffer = zeros(T,nEch * depth)
        return new{T}(lock,buffer,nEch,depth)    
    end
end 


""" Structure for Atomic (i.e Thread safe) variable managment 
"""
mutable struct AtomicValue{T}
    ptr::T 
    lock::ReentrantLock 
end

""" Thread Safe circular buffer 
"""
mutable struct AtomicCircularBuffer{T}
    ptr_write::AtomicValue{Int}
    ptr_read::AtomicValue{Int} 
    buffer::AtomicBuffer{T}
    t_new::AtomicValue{Int}
    t_stop::AtomicValue{Int}
    function AtomicCircularBuffer{T}(nEch::Int,depth::Int) where T
        buffer = AtomicBuffer{T}(nEch,depth)
        ptr_w  = AtomicValue{Int}(0,ReentrantLock())
        ptr_r  = AtomicValue{Int}(0,ReentrantLock())
        t_new  = AtomicValue{Int}(0,ReentrantLock())
        t_stop = AtomicValue{Int}(0,ReentrantLock())
        return new{T}(ptr_w,ptr_r,buffer,t_new,t_stop)
    end
end


# ----------------------------------------------------
# --- Atomic functions 
# ---------------------------------------------------- 

""" Safely read an atomic value 
"""
@inline function atomic_read(ptr::AtomicValue)
    lock(ptr.lock) do 
        return ptr.ptr
    end
end

#""" Safely read an atomic buffer circularly
#"""
#function atomic_read(buffer::AtomicBuffer,i::Int)
#lock(buffer.lock[1+i]) do 
#return buffer.buffer[i*buffer.nEch .+ (1:buffer.nEch)] 
#end
#end

""" Update the counter position for read/write, in a safe way 
"""
@inline function atomic_update(ptr::AtomicValue,depth) 
    lock(ptr.lock) do 
        ptr.ptr = mod(ptr.ptr+1,depth)
    end
end

""" Safely write a buffer in the atomic circular buffer.
It assumes that data has the same size as the buffer 
"""
function atomic_write(buffer::AtomicBuffer,data,i)
    @assert length(data) == buffer.nEch "When filling the atomic circular buffer data (length $(length(data))) should have the same size as the internal buffer (length $(buffer.nEch))"
    lock(buffer.lock[1+i]) do 
        copyto!(buffer.buffer,i*buffer.nEch .+ (1:buffer.nEch),data,(1:buffer.nEch))
    end
end 


""" Value that states a new data is available 
""" 
function atomic_prodData(ptr::AtomicValue,depth) 
    lock(ptr.lock) do 
        ptr.ptr = min(ptr.ptr+1,depth)
    end
end

""" Update the value to state a new data has been consummed 
"""
function atomic_consData(ptr::AtomicValue) 
    lock(ptr.lock) do 
        ptr.ptr = max(ptr.ptr-1,0) 
    end
end

#function atomic_stop(buffer::AtomicCircularBuffer) 
    #lock(buffer.t_stop.lock) do 
        #buffer.t_stop.ptr = 1
    #end
#end

""" Waiting function. Blocks until a new data is available. 
"""
function wait_consData(circ_buff)
    new_data = false 
    while (new_data == false)
        flag = atomic_read(circ_buff.t_new) 
        #stop =  atomic_read(circ_buff.t_stop) 
        new_data = (flag > 0) 
        yield() 
    end
end
# ----------------------------------------------------
# --- Producer
# ---------------------------------------------------- 
""" Put the new data in the circular buffer 
"""
function circ_put!(circ_buff::AtomicCircularBuffer{T},data::Vector{T}) where T 
    # Where put data ? 
    pos = atomic_read(circ_buff.ptr_write)
    #@info  "Tx => $pos"
    # Put data 
    atomic_write(circ_buff.buffer,data,pos)
    # Update pointer 
    atomic_update(circ_buff.ptr_write,circ_buff.buffer.depth)
    # New data 
    atomic_prodData(circ_buff.t_new,circ_buff.buffer.depth)
    yield()
end 
# ----------------------------------------------------
# --- Consummers
# ---------------------------------------------------- 
""" Get the last buffer of the circular buffer, as soon as new data is available 
"""
function circ_take!(buffer::Vector{T},circ_buff::AtomicCircularBuffer{T}) where T
    # Where take data ?
    nEch = circ_buff.buffer.nEch
    wait_consData(circ_buff)
    pos = atomic_read(circ_buff.ptr_read)
    lock(circ_buff.buffer.lock[1+pos]) do 
        copyto!(buffer,1:nEch,circ_buff.buffer.buffer,pos*nEch .+ (1:nEch))
    end
    # Update pointer 
    atomic_update(circ_buff.ptr_read,circ_buff.buffer.depth)
    # we have a new data
    atomic_consData(circ_buff.t_new)
end
end
using .AtomicCircularBuffers

# ----------------------------------------------------
# --- Structure 
# ---------------------------------------------------- 
""" A small structure to keep timing and buffer measure to calculate SDR rate 
"""
mutable struct Rate 
    tInit::Float64  # Init timing for processing 
    tFinal::Float64 # End of timing for processing 
    cnt::Int  # Number of buffers processed 
    cnt_prod::Int # Internal counter for producer to track overflows
end

function initRate(rate::Rate,offset=0)
    rate.tFinal = -1  # Final time to -1 as it is not finished 
    rate.cnt = 0 # Number of current process items 
    rate.cnt_prod = offset # Start value of the SDR internal counter  
    rate.tInit = time() # Timing of origins
end




mutable struct AtomicAbstractSDR 
    sdr::AbstractSDR
    buffer::Vector{ComplexF32} 
    bufferSize::Int
    circ_buff::AtomicCircularBuffer{ComplexF32} 
    nbStored::Int 
    stopRadio::Bool
    rate_producer::Rate 
    rate_consummer::Rate
end

# ----------------------------------------------------
# --- Manager
# ---------------------------------------------------- 
function initRateProducer(csdr)
    initRate(csdr.rate_producer)
end
function initRateConsummer(csdr) 
    initRate(csdr.rate_consummer,csdr.nbStored)
end
function updateRateProducer(csdr::AtomicAbstractSDR)
    csdr.rate_producer.tFinal = time()
    csdr.rate_producer.cnt = csdr.nbStored
end
""" Update the rate metric for consummer, assuming we have process `cnt` buffers
"""
function updateRateConsummer(csdr::AtomicAbstractSDR,cnt)
    csdr.rate_consummer.tFinal = time()
    csdr.rate_consummer.cnt = cnt
    csdr.rate_consummer.cnt_prod = csdr.nbStored - csdr.rate_consummer.cnt_prod
end
function getProducerRate(csdr::AtomicAbstractSDR)
    if csdr.rate_producer.tFinal == -1 
        @warn "Unable to process rate, process is not terminated (call `updateRateProducer`)"
    end
    Δ = csdr.rate_producer.tFinal - csdr.rate_producer.tInit 
    rate = round(csdr.rate_producer.cnt* length(csdr.buffer)/ Δ / 1e6;digits=2)
    return rate
end
function getConsummerRate(csdr::AtomicAbstractSDR)
    if csdr.rate_consummer.tFinal == -1 
        @warn "Unable to process rate, process is not terminated (call `updateRateConsummer`)"
    end
    Δ = csdr.rate_consummer.tFinal - csdr.rate_consummer.tInit 
    rate = round(csdr.rate_consummer.cnt* length(csdr.buffer)/ Δ / 1e6;digits=2)
    return rate
end
function getConsummerOverflow(csdr::AtomicAbstractSDR) 
    nb_p  = csdr.rate_consummer.cnt_prod
    nb_c  = csdr.rate_consummer.cnt 
    overflow = max(0, nb_p - nb_c)
    return overflow
end 


""" Open a remote SDR system. It consists with an SDR on a specific Core (with no others processing tasks and a circular buffer managment on the processing core 
"""
function openAtomicSDR(args...;bufferSize=1024,circular_depth=16,kw...)
    sdr = openSDR(args...;kw...) 
    buffer  = zeros(ComplexF32,bufferSize)
    circ_buff = AtomicCircularBuffer{ComplexF32}(bufferSize,circular_depth)
    r1 = Rate(0,0,0,0)
    r2 = Rate(0,0,0,0)
    return AtomicAbstractSDR(sdr,buffer,bufferSize,circ_buff,0,false,r1,r2)
end

""" Start the process. This function should be called with Threads.@spawn (see `start_atomic_sdr`)
"""
function start_atomic_sdr(csdr::AtomicAbstractSDR)
    csdr.stopRadio = false
    # Counter and timing for rate calculation 
    cnt = 0 
    initRateProducer(csdr)
    try 
        # While loop to have continunous streaming 
        while (csdr.stopRadio == false)
            # Fill the working buffer 
            recv!(csdr.buffer,csdr.sdr)
            # Copy at good position of circular buffer
            circ_put!(csdr.circ_buff,csdr.buffer)
            # --- Push on the atomic circular buffer
            csdr.nbStored += 1
            cnt += 1
            yield()
        end
    catch exception 
        rethrow(exception)
    end
    updateRateProducer(csdr)
    return getProducerRate(csdr)
end

function stop_atomic_sdr(csdr) 
    csdr.stopRadio = true 
end

function recv!(buffer,csdr::AtomicAbstractSDR)
    circ_take!(buffer,csdr.circ_buff)
end

function close(csdr::AtomicAbstractSDR) 
    sleep(0.1)
    close(csdr.sdr)
end


function _customPrint(str,handler;style...)
    msglines = split(chomp(str), '\n')
    printstyled("┌",handler,": ";style...)
    println(msglines[1])
    for i in 2:length(msglines)
        (i == length(msglines)) ? symb="└ " : symb = "|";
        printstyled(symb;style...);
        println(msglines[i]);
    end
end

function print_summary(csdr::AtomicAbstractSDR)
    r_p = getProducerRate(csdr)
    r_c = getConsummerRate(csdr)
    overflow = getConsummerOverflow(csdr)
    Fs = round(getSamplingRate(csdr.sdr)/1e6;digits=2)
    str = "SDR sampling frequency : $Fs MHz\nProducer side: $(r_p) MS/s [$(csdr.nbStored) produced buffers]\nConsummer side: $(r_c) MS/s [$overflow overflows]"
    # To print fancy message with different colors with Tx and Rx
    _customPrint(str,"Atomic SDR Summary";bold=true,color=:light_magenta)
end


end

