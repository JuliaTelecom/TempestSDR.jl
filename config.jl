# ----------------------------------------------------
# --- SDR configuration 
# ---------------------------------------------------- 
# Simulation or Real mode ?
# - :radiosim will use a file for IQ samples (located in ./src_tempest/TempestSDR/dumpIQ_0.dat 
# - :pluto will use a plugged AdalmPluto for real eavesdrop 
sdr   = :radiosim# change to sdr = :pluto for real SDR use 
sdr = :pluto
# Add here all the keywords related to the radio use 
kw =(;
    )
# Example, with a Pluto SDR with address "usb:1.0.0.5"
# use kw = (;addr="usb:1.0.0.5")

# ----------------------------------------------------
# --- Carrier, band and Gain configuration 
# ---------------------------------------------------- 
carrierFreq  = 764e6        # Carrier, in Hz 
samplingRate = 20e6         # Band, in Hz 
gain         = 9            # Radio Gain 
acquisition  = 0.05         # Duration of internal bursts (no need to modify this)





