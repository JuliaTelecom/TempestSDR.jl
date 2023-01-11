using Sockets 
using TempestSDR

carrierFreq  = 764e6
samplingRate = 4e6 
gain         = 20 
acquisition   = 0.5 


nbS = Int( samplingRate * acquisition)
sigRx = repeat(1:8,1,nbS)'[:]
csdr = configure_sdr(:radiosim,carrierFreq,samplingRate,gain;addr="usb:1.8.5",depth=256,buffer=sigRx,bufferSize=nbS,packetSize=nbS)


task_producer = @async circ_producer(csdr) 
task_consummer= @async circ_consummer(csdr)


sleep(10)
circ_stop(csdr)






#AbstractSDRs.recv!(csdr.buffer,csdr.sdr) ; circ_put!(circ_buff,csdr.buffer); csdr.buffer[1]


#global circ_buff = init_circ_buff(nbS)
#global RUN = true 

#@async begin 
    #cnt = 0 
    #while (RUN == true)
        #AbstractSDRs.recv!(csdr.buffer,csdr.sdr)
        #circ_put!(circ_buff,csdr.buffer)
        #yield()
    #end 
    #@info "done"
#end 

#@async begin 
    #cnt = 0 
    #while (RUN == true)
        #circ_take!(circ_buff)
        #yield()
    #end 
    #@info "done"
#end 
