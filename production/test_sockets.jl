using Sockets 
using TempestSDR
using AbstractSDRs

carrierFreq  = 764e6
samplingRate = 4e6 
gain         = 20 
acquisition   = 2 


nbS = Int( samplingRate * acquisition)
sigRx = repeat(1:8,1,nbS)'[:]
csdr = configure_sdr(:radiosim,carrierFreq,samplingRate,gain;addr="usb:0.10.5",depth=256,buffer=sigRx,bufferSize=nbS,packetSize=nbS)


task_producer = @async circ_producer(csdr) 
task_consummer= @async circ_consummer(csdr)
 #circ_consummer(csdr)


#sleep(2)
#circ_stop(csdr)
#close(csdr)
