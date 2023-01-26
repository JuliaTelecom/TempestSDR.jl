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
#    function AtomicBuffer(nEch::Int,depth::Int)
        #lock   = [ReentrantLock() for _ ∈ 1 : depth]
        #buffer = zeros(ComplexF32,nEch * depth)
        #return new{ComplexF32}(lock,buffer,nEch,depth)       
    #end
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

""" Safely read an atomic buffer circularly
"""
function atomic_read(buffer::AtomicBuffer,i::Int)
    lock(buffer.lock[1+i]) do 
        return buffer.buffer[i*buffer.nEch .+ (1:buffer.nEch)] 
    end
end

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
        buffer.buffer[i*buffer.nEch .+ (1:buffer.nEch)]  = deepcopy(data)
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

function atomic_stop(buffer::AtomicCircularBuffer) 
    lock(buffer.t_stop.lock) do 
        buffer.t_stop.ptr = 1
    end
end

""" Waiting function. Blocks until a new data is available. 
"""
function wait_consData(circ_buff)
    new_data = false 
    while (new_data == false)
        flag = atomic_read(circ_buff.t_new) 
        stop =  atomic_read(circ_buff.t_stop) 
        new_data = (flag > 0) || stop == 1
        yield() 
    end
end

# ----------------------------------------------------
# --- Producer
# ---------------------------------------------------- 
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
function circ_take!(buffer::Vector{T},circ_buff::AtomicCircularBuffer{T}) where T
    # Where take data ?
    wait_consData(circ_buff)
    pos = atomic_read(circ_buff.ptr_read)
    #@info  "Rx => $pos"
    # Put data 
    buffer.= atomic_read(circ_buff.buffer,pos)
    # Update pointer 
    atomic_update(circ_buff.ptr_read,circ_buff.buffer.depth)
    atomic_consData(circ_buff.t_new)
end




end
