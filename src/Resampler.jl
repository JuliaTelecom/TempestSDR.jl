module Resampler 
# Module for efficiently change the rate of the signal


# ----------------------------------------------------
# --- Dependencies 
# ---------------------------------------------------- 
using FFTW 
using LinearAlgebra
using DSP 
using Images

# ----------------------------------------------------
# --- Exports
# ---------------------------------------------------- 
export init_resampler
export naiveResampler
export sig_to_image
export downgradeImage
# ----------------------------------------------------
# --- Methods
# ---------------------------------------------------- 

""" Clojure to instantiate the resampling (upsampling) method
"""
function init_resampler(T::Type,bufferSize::Int, upCoeff::Int)
    sizeFFT = bufferSize * upCoeff
    # Dummy vector to instantiate the FFT plan
    # We swith input in freq domain to perform filtering in frequency domain
    dummy = ones(T,sizeFFT)
    planFFT = plan_fft(dummy;flags=FFTW.PATIENT);
    # Container for FFT 
    # Input will be zero padded
    containerFFT = zeros(Complex{T},sizeFFT)
    inFFT = zeros(Complex{T}, sizeFFT)
    # Instantiate Low pass filter, in frequency domain 
    H,_ = initLPF(T,sizeFFT, upCoeff)
    # Plan for inverse fourier transform 
    planIFFT 	= plan_ifft(dummy;flags=FFTW.PATIENT);
    outFFT = zeros(Complex{T}, sizeFFT)

    function resampler!(out::AbstractVector{T2},in::AbstractVector{T2}) where T2
        # Check if types are compatible 
        @assert T == T2 "Type of input ($T2) should match type used during init ($T)"
        # Switch input in frequency domain 
        N = length(in) 
        @assert length(in) == bufferSize "Size of input $N should match size used during init $bufferSize"
        containerFFT[1:upCoeff:end] .= in 
        mul!(inFFT,planFFT,containerFFT)
        # --- Filtering in frequency domain 
        @inbounds @simd for n ∈ eachindex(inFFT)
            inFFT[n] = inFFT[n] * H[n] 
        end
        # Back in time domain, but in complex 
        mul!(outFFT,planIFFT,inFFT)
        # Output in real domain
        @inbounds @simd for n ∈ eachindex(outFFT)
            out[n] = 2*upCoeff*real(outFFT[n])
        end
    end
    return resampler!
end


function init_resampler(x::Vector{T},upCoeff) where T
    # Dispatch
    init_resampler(T,length(x),upCoeff)
end


""" Init Low pass filter in frequency domain, based on filter synthesis method.
It takes the length of the filter in frequency domain and the upscaling parameters. The associated filter LPF will be 1/upCoeff in normalized units

initLPF(T,sizeFFT,upCoeff)
- T : Type of input (Float32, Float64...)
- sizeFFT : Size of the filter in frequency domain 
- upCoeff : Factor of upscaling. The filter should cut at π / upCoeff

Returns 
- H : Filter in frequency domain (Vector of size sizeFFT)
- h : Filter impulse response (Vector of size sizeFFT)
"""
function initLPF(T,sizeFFT,upCoeff)
    # --- Filter in freq domain, magnitude 
    H = zeros(Complex{T},sizeFFT) 
    bound = round( sizeFFT / upCoeff / 2) |> Int 
    H[1:bound] .= 1 
    # --- Adding linear phase term
    pulsation	= 2*π*(0:sizeFFT-1)/sizeFFT;	# --- Pulsation \Omega 
    groupDelay	= - (sizeFFT-1)/2;			# --- Group delay 
    H		.= round.(H .* exp.(1im* groupDelay * pulsation))
    # Apodisation 
    w = blackman(sizeFFT)
    # Filter in time domain with apodisation 
    h = ifft(H) .* w 
    # Filter in frequency domain 
    H = fft(h) .* (-1).^(0:sizeFFT-1)
    return (H,h)
end



function naiveResampler(sigOut,sigId,upCoeff)
    #@assert length(sigOut) == upCoeff * length(sigId) "Output out ($(length(sigOut))) should be $upCoeff x $(length(sigId))"
    for n ∈ eachindex(sigId)
        for k ∈ 1 : upCoeff
            sigOut[(n-1)*upCoeff + k] = sigId[n]
        end
    end
end



""" Transform a signal to an image of size x_t*y_t
Note that this is for rendering and that this matrix should be transposed in order to have the pixel at the right position 
"""
function sig_to_image(sig,y_t,x_t)
    image_size = y_t * x_t
    image_mat  = collect(transpose(reshape(imresize(sig,image_size),x_t,y_t)))
    #image_mat  = transpose(reshape(imresize(sig,image_size),y_t,x_t))
    return image_mat
end

function downgradeImage(image)
    return imresize(image,(600,800))
end


end
