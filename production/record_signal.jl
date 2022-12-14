using TempestSDR 
using AbstractSDRs



# ----------------------------------------------------
# --- Configuration
# ---------------------------------------------------- 
carrierFreq = 763.9e6
bandwidth = 32e6 
gain = 22 
duration = 8
#addr = "192.168.10.15"
addr = "192.168.40.2"
usb = "usb:0.4.5"

# ----------------------------------------------------
# --- Open and configure SDR 
# ---------------------------------------------------- 
sdr = openSDR(:uhd,carrierFreq,bandwidth,gain;args="addr=$addr",backend="usb")
print(sdr)
sleep(3.0)
println("Start")
# ----------------------------------------------------
# --- Receive samples 
# ---------------------------------------------------- 
n = Int(round(duration * bandwidth))
sigRx = recv(sdr,n)
sigId = abs2.(sigRx)


close(sdr)
writeComplexBinary(sigRx,"/Users/Robin/data_tempest/x310.dat")

tup = getSpectrum(bandwidth,sigRx[1:80_000]);pFreq = fig(); plot!(pFreq,x=tup[1],y=tup[2]);


