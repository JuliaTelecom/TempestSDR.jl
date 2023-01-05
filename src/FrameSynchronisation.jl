module FrameSynchronisation 


# ----------------------------------------------------
# --- Dependencies 
# ---------------------------------------------------- 
using DSP 
using LoopVectorization
# ----------------------------------------------------
# --- Exportations
# ---------------------------------------------------- 
export init_vsync
export vSync


# ----------------------------------------------------
# --- Methods definitions 
# ---------------------------------------------------- 
# Internal structure to find the frame start
struct Sync
    w_min::Int  # Minimum blank duration 
    w_max::Int  # Maximum blank duration 
    n::Int      # Size of the line or column
end 



function init_vsync(image::AbstractArray{T}) where T
    # Size of the image 
    (y_t,x_t) = size(image)
    # Init container 
    c_v = zeros(T, x_t)
    c_h = zeros(T, y_t)
    # Initiate Gaussian filter 
    h   = init_gaussian_filter(5)
    # Bounds for β search 
    @show wmin_y = Int(ceil(1/100*y_t))
    @show wmax_y   = Int(floor(y_t/4))
    β_y    = zeros(T,1+wmax_y - wmin_y,y_t)
    # Bounds for β search 
    @show wmin_x = Int(ceil(5/100*x_t))
    @show wmax_x   = Int(floor(x_t/4))
    β_x    = zeros(T,1+wmax_x - wmin_x,x_t)


    sync_y = Sync(wmin_y,wmax_y,y_t)
    sync_x = Sync(wmin_x,wmax_x,x_t)


    # Clojure for sync 
#    function vsync(image)
        ## Average on vertical limit 
        #c_v  = sum(image;dims=1)
        ## Filtering with the Gaussian kernel 
        #c_v  = filt(h,c_v)
        #@inbounds for (iw,w) in enumerate(wmin_y : wmax_y)
            #for c in 1 : y_t 
                #β_y[iw,c] = (sum( [c_v[modIndex(k,y_t)]/2w for k ∈ c-w:c+w]) - sum([ c_v[modIndex(k,y_t)]/(2y_t-4w) for k ∈ 2w-c : 2(y_t-w)-c]))^2
            #end 

        #end
        ## Average on horizontal limit 
        #c_h  = sum(image;dims=2)
        ## Filtering with the Gaussian kernel 
        #c_h  = filt(h,c_h)
        #@inbounds for (iw,w) in enumerate(wmin_x : wmax_x)
            #for c in 1 : x_t 
                #β_x[iw,c] = (sum( [c_v[modIndex(k,x_t)]/2w for k ∈ c-w:c+w]) - sum([ c_v[modIndex(k,x_t)]/(2x_t-4w) for k ∈ 2w-c : 2(x_t-w)-c]))^2
            #end 
        #end
        #@show s_y = findmax(β_y)[2]
        #@show s_x = findmax(β_x)[2]
        #return (s_x,s_y)
    #end
    
    function vsync(image)
        # Average on vertical limit 
        c_v  = sum(image;dims=1)
        # Filtering with the Gaussian kernel 
        c_v  = filt(h,c_v)
        # Find y position 
        @show sync_y
        fill_β!(β_y,c_v,sync_y)
        @show s_y = findmax(β_y)[2]
         # Average on vertical limit 
        c_h  = sum(image;dims=1)
        # Filtering with the Gaussian kernel 
        c_h  = filt(h,c_h)       
        # Find x position 
        fill_β!(β_x,c_h,sync_x)
        @show s_x = findmax(β_x)[2]
        return (s_x,s_y)
    end
    
    return vsync
end

function vSync(anImage::Matrix{T}) where T
    # Size of the image 
    (y_t,x_t) = size(anImage)
    # Init container 
    c_v = zeros(T, x_t)
    c_h = zeros(T, y_t)
    # Initiate Gaussian filter 
    h   = init_gaussian_filter(5)
    # Bounds for β search 
    wmin_y = Int(ceil(1/100*y_t))
    wmax_y   = Int(floor(y_t/4))
    β_y    = zeros(T,1+wmax_y - wmin_y,y_t)
    # Bounds for β search 
    wmin_x = Int(ceil(5/100*x_t))
    wmax_x   = Int(floor(x_t/4))
    β_x    = zeros(T,1+wmax_x - wmin_x,x_t)
    # Synchronizer operator 
    sync_y = Sync(wmin_y,wmax_y,y_t)
    sync_x = Sync(wmin_x,wmax_x,x_t)
    # Calling main procedure 
    # Average on vertical limit 
    c_v  = sum(anImage;dims=1)
    # Filtering with the Gaussian kernel 
    c_v  = filt(h,c_v)
    # Find y position 
    fill_β2!(β_y,c_v,sync_y)
    s_y = findmax(β_y)[2]
    # Average on vertical limit 
    c_h  = sum(anImage;dims=1)
    # Filtering with the Gaussian kernel 
    c_h  = filt(h,c_h)       
    # Find x position 
    fill_β2!(β_x,c_h,sync_x)
    s_x = findmax(β_x)[2]
    return (s_x,s_y,β_x,β_y)
end



@inline function calculate_β(c_v,w,c,n)
    accum = 0 
    @inbounds @simd for k ∈ c-w : c+w 
        accum += c_v[modIndex(k,n)] 
    end 
    accum = accum / 2w 
    accum2 = 0
    @inbounds @simd for k ∈ 2w - c : 2(n-w) - c 
        accum2 +=  c_v[modIndex(k,n)]
    end 
    accum2 = accum2 / (2n-4w)
    return (accum+accum2)^2
end


function fill_β!(β,c_v,sync::Sync)
    cnt = 1 
    for w ∈ sync.w_min : sync.w_max
        for c ∈ 1 : sync.n 
            β[cnt,c] = calculate_β(c_v,w,c,sync.n)
        end
        cnt += 1
    end
end


function neightbor(c_v,c,w,n)
    accum = 0
    for k ∈ c - w : c + w 
        accum += c_v[modIndex(k,n)]
    end
    return accum 
end

""" A fast version to compute the energy difference for the anImage 
"""
function fill_β2!(β,c_v,sync::Sync)
    # Energy of total stripe
    Σ = sum(c_v) 
    # centering in c 
    for c ∈ 1 : sync.n 
        # Remove smallest neightbor. We remove 1 to this area to be able to loop on the complete area
        _Σ = 2*neightbor(c_v,c,sync.w_min-1,sync.n) 
        # Calculate for all w 
         cnt = 1
        for w ∈ sync.w_min : sync.w_max
            _Σ += 2*c_v[modIndex(c-w,sync.n)] 
            _Σ += 2*c_v[modIndex(c+w,sync.n)] 
            β[cnt,c] = ((Σ - _Σ)/(2(sync.n-w)) + (_Σ) / 2w).^2
            cnt += 1
        end
    end
end


""" Apply a modulo operation for index but with 1 indexing 
mod(512,512) = 1 
mod(1,512) = 1 
mod(37,512) = 37
"""
function modIndex(k,n)
    return 1 + mod(k-1,n)
end

function init_gaussian_filter(N)
    @assert isodd(N) "For Gaussian filter, the order should be odd"
    α = (N-1)÷2
    h = [exp(-2*k^2/N^2) for k ∈ -α:α]
    return h ./ sum(h)
end



end
