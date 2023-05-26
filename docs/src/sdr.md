## Using a real SDR for a real eavesdrop 

The command 


        using TempestSDR 
        tup = gui(;sdr=:radiosim,carrierFreq=764e6,samplingRate=20e6,gain=9,acquisition=0.05);

uses a virtual radio populated by the given signal (which has a screen eavesdrop inside).


While it is a first try, the real interest lies when a real SDR is used, by trying to intercept a real screen. 

What you need to do this ?

- A SDR supported by AbstractSDRs (an USRP, a BladeRF or a Pluto). If you have an SDR that is not supported by any AbstractSDRs backend, feel free to open a PR on AbstractSDRs 

- A setup to attack: a PC (laptop or tower) connected to a screen by a VGA or HDMI cable. First, position your SDR near to the PC to attack in order to enhance the received Signal to Noise Radio (SNR). After you have obtain an image, you can move the SDR far from the attacked PC.  

Then, launch the GUI by setting the proper SDR backend. For instance if you use an AdalmPluto from Analog device, you can run


        using TempestSDR 
        tup = gui(;sdr=:pluto,carrierFreq=764e6,samplingRate=20e6,gain=9,acquisition=0.05);

Note that you can add any specific keywords associated to the radio configuration such as the address of the SDR 

        using TempestSDR 
        tup = gui(;sdr=:pluto,carrierFreq=764e6,samplingRate=20e6,gain=9,acquisition=0.05,addr="usb:1.0.5");


You have to tune the carrier frequency to find a potential leakage. When choosing a carrier frequency, remain to important things  

- Leakage appears at multiple  of screen clock (often multiple of 148,5MHz ) 
- If you detect EM activities, the correlation should have variations. If you encounter many peaks, this is a good sign as it means that this EM  signature has patterns   


