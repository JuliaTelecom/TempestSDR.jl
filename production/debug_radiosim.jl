# --- Dependencies 
# ---------------------------------------------------- 
include("../setMP.jl")
using TempestSDR 
using AbstractSDRs

# ----------------------------------------------------
# --- Loading signal 
# ---------------------------------------------------- 
const DATA_PATH = "./data"
const BANDWIDTH = 20           # Targetting Band: 4, 20 or 200 MHz
Fs::Float64 = BANDWIDTH * 1e6 
#sigId = readComplexBinary("$DATA_PATH/tempest_screen_$BANDWIDTH.dat",:short)
#completePath = "$(pwd())/$DATA_PATH/testPluto.dat"

try IS_LOADED == true
catch exception 
    #local completePath = "$(pwd())/$DATA_PATH/testX310.dat"
    local completePath = "/Users/Robin/data_tempest/testX310.dat"
    global sigRx = readComplexBinary(completePath,:single)
    #global sigId = sigRx
    global IS_LOADED = true 
end

import Base:≈
function ≈(c1::VideoMode,c2::VideoMode) 
    return  ((c1.height ≈ c2.height) && (c1.width ≈ c2.width) && (c1.refresh ≈ c2.refresh))
end
function config_with_signal(sigCorr,Fs)
    #global DUMP_CORR = sigCorr
    #sigCorr = Main.DUMP
    (Γ,τ) = calculate_autocorrelation(sigCorr,Fs,0,1/10)
    rates_large,Γ_short_large = zoom_autocorr(Γ,Fs;rate_min=50,rate_max=90)
    # ----------------------------------------------------
    # --- Get the screen rate 
    # ---------------------------------------------------- 
    # ---Find the max 
    (valMax,posMax) = findmax(Γ_short_large)
    posMax_time = 1/rates_large[posMax]
    fv = round(1/ posMax_time;digits=2)
    @info "Position of the max @ $posMax_time seconds [Rate is $fv]"
    # Get the line 
    y_t = let 
        m = findmax(Γ)[2]
        m2 = findmax(Γ[m .+ (1:20)])[2]
        τ = m2 / Fs 
        1 / (fv * τ)
    end
    y_t = 1158
    # ----------------------------------------------------
    # --- Deduce configuration 
    # ---------------------------------------------------- 
    theConfigFound = first(find_closest_configuration(y_t,fv))
    @info "Closest configuration found is $theConfigFound"
    theConfig = theConfigFound[2] # VideoMode config
    theConfig = TempestSDR.allVideoConfigurations["1920x1200 @ 60Hz"]
    finalConfig = VideoMode(theConfig.width,1235,fv)
    @info "Chosen configuration found is $(find_configuration(theConfig)) => $finalConfig"
return finalConfig
end

config_ideal = config_with_signal(sigRx,Fs)


# ----------------------------------------------------
# --- Using SDR
# ---------------------------------------------------- 
carrierFreq  = 764e6
samplingRate = 8e6
gain         = 20 
acquisition   = 0.05
nbS = Int( 80 * 99900)

sdr = openSDR(:radiosim,carrierFreq,buffer=sigRx,bufferSize=nbS,samplingRate,gain;depth=4,addr="usb:0.4.5",packetSize=nbS)

# One recv call 
theSig = recv(sdr,length(sigRx))
config_one_recv = config_with_signal(theSig,Fs)
@assert config_ideal ≈ config_one_recv "Ideal config is not same as 1 recv call"

# Multiple recv call 
nCall = 4
nSe = length(sigRx)÷ nCall
theSig2 = reduce(vcat,[recv(sdr,nSe) for _ in 1 : nCall])
config_multiple_recv = config_with_signal(theSig2,Fs)
@assert config_ideal ≈ config_multiple_recv "Ideal config is not same as multiple recv call"

# Multiple recv call, small signal 
nCall = 1
nSe = length(sigRx)÷ nCall
theSig2 = reduce(vcat,[recv(sdr,nSe) for _ in 1 : nCall])
config_multiple_recv = config_with_signal(theSig2,Fs)
@assert config_ideal ≈ config_multiple_recv "Ideal config is not same as single small recv call"


# Runtime model 
PID_SDR = 1
global channel = RemoteChannel(()->Channel{Vector{ComplexF32}}(1), PID_SDR)
future_prod = @spawnat PID_SDR start_remote_sdr(channel,nbS,:radiosim,carrierFreq,buffer=sigRx,bufferSize=nbS,samplingRate,gain;depth=4,addr="usb:0.4.5",packetSize=nbS)
runtime = init_tempestSDR_runtime(channel,nbS,:terminal)
task_producer = @async circ_producer(runtime.csdr) 
config_runtime = extract_configuration(runtime)

remote_do(stop_remote_sdr,PID_SDR)
sleep(0.1)
# Stopping other calls
stop_processing()


@assert config_ideal ≈ runtime.config  "Ideal config is not same as runtime"
