module Autocorrelations 

# ----------------------------------------------------
# --- Dependencies 
# ---------------------------------------------------- 
using FFTW 

# ----------------------------------------------------
# --- Exportations 
# ---------------------------------------------------- 
export calculate_autocorrelation
export zoom_autocorr

# ----------------------------------------------------
# --- Methods 
# ---------------------------------------------------- 

""" Perform the autocorrelation between in minimal time `minDelay` and a maximal time `maxDelay` assuming that the signal `x` is sampled at the frequency `Fs`.
The output is the log of the square modulus of the correlation and its associated timing indexes.
"""
function calculate_autocorrelation(x,Fs,minDelay,maxDelay;max_size = 65536)
    indexMin = 1+round( minDelay * Fs) |> Int# From duration to index in array 
    indexMax = round( maxDelay * Fs) |> Int
    # --- autocorrelation in frequency domain 
    n     = min(2*indexMax,length(x))
    xFreq = fft(x[1:n])
    theCorr = ifft( xFreq .* conj(xFreq)) / n
    nbS  = indexMax - indexMin 
    lags = (0 : nbS ) * 1/Fs
    return 10*log10.(abs2.(theCorr[indexMin:indexMax])),lags
end


""" Apply a zoom on the autocorrelation to see peaks between `rate_min`He and `rate_max` Hz
"""
function zoom_autocorr(Γ,Fs;rate_min=20,rate_max=100)

    # Defining time grid for Γ 
    N = length(Γ)
    @show pos_rate_min = min(Int( round( 1/rate_max * Fs)),N)
    @show pos_rate_max = min(Int( round( 1/rate_min * Fs)),N)

    xAx = (pos_rate_min : pos_rate_max) ./ Fs
    xARate = 1 ./xAx
    return (xARate, Γ[pos_rate_min:pos_rate_max])

end

end
