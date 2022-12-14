using TempestSDR 
include("/Users/Robin/Desktop/plotUtils.jl")
using DSP



# ----------------------------------------------------
# --- Parameters 
# ---------------------------------------------------- 
Fs = 1e6 
f = 50e3 
f2 = 20e3
L = 1024

t = range(0;step=1/Fs,length=L)
upCoeff = 4

# ----------------------------------------------------
# --- Check filter 
# ---------------------------------------------------- 
(H,h) = TempestSDR.Resampler.initLPF(Float32,L,upCoeff)
(HH,ww) = freqresp(PolynomialRatio(h,[1]))
pFilt = fig()
plot!(pFilt;x=ww,y=10*log10.(abs2.(HH)))



# ----------------------------------------------------
# --- Test signal 
# ---------------------------------------------------- 
x = sin.(2π * f * t) .+ 0.5 * sin.(2π * f2 * t)
resampler! = init_resampler(x,upCoeff)

y = zeros(eltype(x),length(x)*upCoeff)
resampler!(y,x)

y2 = resample(x,upCoeff)

p = fig()
# Display base signal 
plot!(p;x=t,y = x,legend_label="x")
# display oversampled signal 
tUp = range(0;step=1/(upCoeff*Fs),length=length(x)*upCoeff)
plot!(p;x=tUp,y = y,legend_label="y (custom)")
plot!(p;x=tUp,y = y2,legend_label="y (DSP)")
display(p)


using BenchmarkTools
@btime y2 = resample(x,upCoeff)
@btime  resampler!(y,x)
