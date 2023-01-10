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
mutable struct AtomicBuffer 
    lock::ReentrantLock
    buffer::Vector{ComplexF32}
end 

""" Structure for Atomic (i.e Thread safe) variable managment 
"""
mutable struct AtomicValue
    ptr::Int 
    lock::ReentrantLock 
end

""" Thread Safe circular buffer 
"""
mutable struct AtomicCircularBuffer 
    ptr_write::AtomicValue
    ptr_read::AtomicValue 
    buffer0::AtomicBuffer
    buffer1::AtomicBuffer
    buffer2::AtomicBuffer
    buffer3::AtomicBuffer
    t_new::AtomicValue
    t_stop::AtomicValue
    function AtomicCircularBuffer(nbS)
        b0 = init_atomic_buffer(nbS)
        b1 = init_atomic_buffer(nbS)
        b2 = init_atomic_buffer(nbS)
        b3 = init_atomic_buffer(nbS)
        ptr_w = AtomicValue(0,ReentrantLock())
        ptr_r = AtomicValue(0,ReentrantLock())
        t_new = AtomicValue(0,ReentrantLock())
        t_stop = AtomicValue(0,ReentrantLock())
        return new(ptr_w,ptr_r,b0,b1,b2,b3,t_new,t_stop)
    end
end


# ----------------------------------------------------
# --- Atomic functions 
# ---------------------------------------------------- 
function init_atomic_buffer(nbS)
    arr = zeros(ComplexF32,nbS)
    lock = ReentrantLock()
    return AtomicBuffer(lock,arr)
end

@inline function atomic_read(ptr::AtomicValue)
    lock(ptr.lock) do 
        return ptr.ptr
    end
end

function atomic_read(buffer::AtomicBuffer)
    lock(buffer.lock) do 
        return buffer.buffer 
    end
end


@inline function atomic_update(ptr::AtomicValue) 
    lock(ptr.lock) do 
        ptr.ptr = mod(ptr.ptr+1,4)
    end
end

function atomic_write(buffer::AtomicBuffer,data)
    lock(buffer.lock) do 
        buffer.buffer = deepcopy(data)
    end
end 


""" Value that states a new data is available 
""" 
function atomic_prodData(ptr::AtomicValue) 
    lock(ptr.lock) do 
        ptr.ptr = min(ptr.ptr+1,4)
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
        #sleep(0.0001)
    end
end

# ----------------------------------------------------
# --- Producer
# ---------------------------------------------------- 
function circ_put!(circ_buff::AtomicCircularBuffer,data) 
    # Where put data ? 
    pos = atomic_read(circ_buff.ptr_write)
    #@info  "Tx => $pos"
    # Put data 
    (pos == 0) && (atomic_write(circ_buff.buffer0,data))
    (pos == 1) && (atomic_write(circ_buff.buffer1,data))
    (pos == 2) && (atomic_write(circ_buff.buffer2,data))
    (pos == 3) && (atomic_write(circ_buff.buffer3,data))
    # Update pointer 
    pos = atomic_update(circ_buff.ptr_write)
    # New data 
    atomic_prodData(circ_buff.t_new)
    yield()
end 


# ----------------------------------------------------
# --- Consummers
# ---------------------------------------------------- 
function circ_take!(buffer,circ_buff::AtomicCircularBuffer)
    # Where take data ?
    wait_consData(circ_buff)
    pos = atomic_read(circ_buff.ptr_read)
    #@info  "Rx => $pos"
    # Put data 
    (pos == 0) && (buffer.= atomic_read(circ_buff.buffer0))
    (pos == 1) && (buffer.= atomic_read(circ_buff.buffer1))
    (pos == 2) && (buffer.= atomic_read(circ_buff.buffer2))
    (pos == 3) && (buffer.= atomic_read(circ_buff.buffer3))
    # Update pointer 
    pos = atomic_update(circ_buff.ptr_read)
    atomic_consData(circ_buff.t_new)
end




end
