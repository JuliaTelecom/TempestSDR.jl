
# ----------------------------------------------------
# --- Dependencies 
# ---------------------------------------------------- 
using TempestSDR 
using DSP
using Images

# ----------------------------------------------------
# --- Plot system 
# ---------------------------------------------------- 
# We use here our custom Bokeh plotting system 
#include("/Users/Robin/Desktop/plotUtils.jl")


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



sigId = amDemod(sigRx)

# --- In time domain 
#pTime = fig();
#plot!(pTime;y=real(sigId[1:80_000]))

# --- In freq domain
tup = getSpectrum(Fs,sigId[1:80_000])
pFreq = fig()
plot!(pFreq,x=tup[1],y=tup[2])

# ----------------------------------------------------
# --- Get the screen rate
# ---------------------------------------------------- 
toPow(x) = 10*log10(abs2(x))
(Γ,τ) = calculate_autocorrelation(sigId,Fs,0,1/10)

# --- Plot the correlation where it matters
rates_large,Γ_short_large = zoom_autocorr(Γ,Fs;rate_min=50,rate_max=90)
pCorr = fig()
plot!(pCorr;x=rates_large,y=Γ_short_large)

# ---Find the max 
(valMax,posMax) = findmax(Γ_short_large)
posMax_time = 1/rates_large[posMax]
fv = round(1/ posMax_time;digits=2)
@info "Position of the max @ $posMax_time seconds [Rate is $fv]"


# ----------------------------------------------------
# --- Finding number of lines 
# ---------------------------------------------------- 
rates,Γ_short = zoom_autocorr(Γ,Fs;rate_min=fv,rate_max=fv+0.3)

# Creation of an axis related to associated y_t size 


pZoom = fig()
xAx = (0 : length(Γ_short)-1) ./ Fs
plot!(pZoom;x=xAx,y=Γ_short)



y_t = let 
    m = findmax(Γ)[2]
    m2 = findmax(Γ[m .+ (1:20)])[2]
    τ = m2 / Fs 
    1 / (fv * τ)
end
y_t = 1158

# Here we should take the max but in a very local area



# ----------------------------------------------------
# --- Deduce configuration 
# ---------------------------------------------------- 
theConfigFound = first(find_closest_configuration(y_t,fv))
@info "Closest configuration found is $theConfigFound"
theConfig = theConfigFound[2] # VideoMode config

theConfig = TempestSDR.allVideoConfigurations["1920x1200 @ 60Hz"]
finalConfig = VideoMode(theConfig.width,1235,fv)

@info "Chosen configuration found is $(find_configuration(theConfig)) => $finalConfig"


#function slidingCorr(sigId::Vector{T},Fs,screenRate) where T
    #support = Int(round(Fs / screenRate))
    #@show τ = min(100_000,length(sigId) - support)
    #slider  = zeros(T,support)
    #@inbounds @simd for n ∈ eachindex(slider)
        #slider[n] = sum( sigId[1:τ] .* sigId[(n).+(1:τ)])
    #end
    #return slider
#end
#syncTime = slidingCorr(sigId,Fs,fv)


#pSlide = fig()
#plot!(pSlide;y=syncTime)

##function createImage!(image_mat,theView,x_t,y_t,upCoeff)
    ##sigUp = resample(theView,upCoeff)
    ##image_mat .= reshape(sigUp[1:Int(x_t*y_t)],Int(y_t),Int(x_t))
##end

#indexSync = findmax(syncTime)[2]
#sigSync = sigId[indexSync:end]



# ----------------------------------------------------
# --- Fine frame synchronisation
# ---------------------------------------------------- 



# ----------------------------------------------------
# --- Example image 
# ---------------------------------------------------- 
durationImage =  Int(round(Fs / fv))

function singleProcessing(sigId,offset,durationImage,finalConfig)
    viewSig = abs2.(sigId[(offset) .+ (1:durationImage)])

    outSize = finalConfig.width * finalConfig.height 
    anImage = transpose(reshape(imresize(viewSig,outSize),finalConfig.width,finalConfig.height))


    screen = initScreenRenderer(finalConfig.height,finalConfig.width)
    displayScreen!(screen,anImage)

    return screen


end

#pPower = fig()
#plot!(pPower;y=abs2.(sigId[1:1_000:end]))

""" Create an Image based on the input signal, its sampling frequency, the video configuration. The parameter offset setup the offset from which the image will be generated 
Returns an image of size finalConfig.width x finalConfig.heigth 
"""
function toImage(sigId,offset,Fs,finalConfig)
    # Duration of Image based on current configuration 
    d = Int(round(Fs/finalConfig.refresh))
    # View on the signal 
    s = sigId[(offset).+(1:d)]
    # Size of the image 
    outSize = finalConfig.width * finalConfig.height 
    # Convert into Image using lines and columns 
    anImage = collect(transpose(reshape(imresize(s,outSize),finalConfig.width,finalConfig.height)))
    return anImage 
end

anImage = toImage(sigId,4_200_000,Fs,finalConfig)

# ----------------------------------------------------
# --- Frame sync
# ---------------------------------------------------- 
vSync = init_vsync(anImage)
tup = vSync(anImage)
#terminal_with_sync(anImage,tup[2][2],tup[1][2])


τ = tup[2][2] * finalConfig.width + tup[1][2]
idx = Int(floor(τ / (finalConfig.width * finalConfig.height)  / fv * Fs))

anImage = toImage(sigId,4_200_000 +idx, Fs,finalConfig)
#terminal(anImage)
