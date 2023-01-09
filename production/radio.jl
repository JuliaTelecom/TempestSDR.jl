using TempestSDR 
using AbstractSDRs


include("../setMP.jl")


carrierFreq  = 764e6
samplingRate = 4e6 
gain         = 20 
acquisition   = 2 

nbS = Int( acquisition * samplingRate )
#completePath = "/Users/Robin/data_tempest/testX310.dat"
#sigRx = readComplexBinary(completePath,:single)


csdr = configure_sdr(:pluto,carrierFreq,samplingRate,gain;addr="usb:0.10.5",depth=256,bufferSize=nbS)


#@async circular_start(csdr)

#@async begin 
    #sleep(5)
    #circular_stop()
#end 

#coreProcessing(csdr,Fs,finalConfig;renderer=:terminal)


#buffer = recv(sdr,nbS) 

@spawnat 1 circular_sdr_start(csdr) 
finalConfig = extract_configuration(csdr) 
coreProcessing(csdr,finalConfig;renderer=:gtk);
stop_processing(csdr)

#close(sdr)
