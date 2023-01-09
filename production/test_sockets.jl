using Sockets 
using TempestSDR


carrierFreq  = 764e6
samplingRate = 4e6 
gain         = 20 
acquisition   = 2 

nbS = Int( acquisition * samplingRate )
completePath = "/Users/Robin/data_tempest/testX310.dat"
sigRx = readComplexBinary(completePath,:single)


csdr = configure_sdr(:radiosim,carrierFreq,samplingRate,gain;addr="usb:0.10.5",depth=256,buffer=sigRx,bufferSize=nbS)


tt = @async  circular_sdr_start(csdr) 


sleep(2)
circular_sdr_stop(csdr)
#close(csdr)
