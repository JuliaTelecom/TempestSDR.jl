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

    function vsync(image)
        # Average on vertical limit 
        c_v  = sum(image;dims=1)
        # Filtering with the Gaussian kernel 
        c_v  = filt(h,c_v)
        # Find y position 
        fill_β!(β_y,c_v,sync_y)
        s_y = findmax(β_y)[2]
         # Average on vertical limit 
        c_h  = sum(image;dims=1)
        # Filtering with the Gaussian kernel 
        c_h  = filt(h,c_h)       
        # Find x position 
        fill_β!(β_x,c_h,sync_x)
        s_x = findmax(β_x)[2]
        return (s_x,s_y)
    end
    
    return vsync
end

""" Calculate the average pixel in the blank area of width `w` for an flatten image `c_v` of size `n` and assuming that the blank area is centered at `c`
"""
function averagePixel(c_v,c,w,n)
    accum = 0
    for k ∈ c - w : c + w 
        accum += c_v[modIndex(k,n)]
    end
    return accum 
end

""" A fast version to compute the energy difference for the anImage 
"""
function fill_β!(β,c_v,sync::Sync)
    # Energy of total stripe
    Σ = sum(c_v) 
    # centering in c 
    for c ∈ 1 : sync.n 
        # Remove smallest neightbor. We remove 1 to this area to be able to loop on the complete area
        # This is the minimal blank region. All other regions (for larger values of w) will contains _Σ
        _Σ = 2*averagePixel(c_v,c,sync.w_min-1,sync.n) 
        # Calculate for all w 
         cnt = 1
        for w ∈ sync.w_min : sync.w_max
            # For larger values of blank regions, this is _Σ with the additional pixels on left and right
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
