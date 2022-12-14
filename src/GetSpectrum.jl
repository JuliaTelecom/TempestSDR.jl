module GetSpectrum

# ----------------------------------------------------
# --- Dependencies 
# ---------------------------------------------------- 
using FFTW 

# ----------------------------------------------------
# --- Exportation 
# ---------------------------------------------------- 
export getSpectrum
export getWaterfall 
export getWelch

# ----------------------------------------------------
# --- Main calls
# ---------------------------------------------------- 
"""
Compute the periodogram of the input signal `sig` sampled at the frequency `fs`. The additional parameter N can be used to restrict the input signal to its N first samples
"""
function getSpectrum(fs,sig;N=nothing)
	if isnothing(N) 
		N = length(sig);
	end
    freqAx = collect(((0:N-1)./N .- 0.5)*fs);
	ss	   = @view sig[1:N];
	y	   = 10*log10.(abs2.(fftshift(fft(ss))));
	return (freqAx,y);
end
getSpectrum(sig) = getSpectrum(1,sig);


"""
Compute the Welch of the input signal `sig` sampled at the frequency `fs` with a FFT size `sizeFFT` . 
"""
function getWelch(fe,sig::Union{Vector{Complex{T}},Vector{T}};sizeFFT=1024) where T
    # --- Define container 
    S = zeros(T,sizeFFT)
    nbSeg = length(sig) ÷ sizeFFT 
    for n ∈ 1 : nbSeg
        # --- Extract current subsignal
        ss = @view sig[(n-1)*sizeFFT.+(1:sizeFFT)]
        # --- Accumulate DFT
        S .+= abs2.(fft(ss))
    end
    # --- Define frequency axis 
    freqAx = collect(((0:sizeFFT-1)./sizeFFT .- 0.5)*fe);
    # --- Compute the PSD 
    y	   = 10*log10.(fftshift(S));
    # --- Output 
	return (freqAx,y);
end

function getWaterfall(fe,sig;sizeFFT=1024)
    nbSeg   = length(sig) ÷ sizeFFT;
    ss      =  @views sig[1:nbSeg*sizeFFT];
    ss      = reshape(ss,sizeFFT,nbSeg)
    sMatrix = zeros(Float64,sizeFFT,nbSeg);
    for iN = 1 : 1 : nbSeg 
        sMatrix[:,iN] = abs2.(fftshift(fft(ss[:,iN])));
    end
    fAx = collect(((0:1:sizeFFT-1)./sizeFFT .- 0.5) .* fe);
    tAx = (0:nbSeg-1) * (sizeFFT/fe);
    return tAx,fAx,sMatrix;
end
getWaterfall(sig;sizeFFT=1024) = getWaterfall(1,sig;sizeFFT=sizeFFT);
end # module

