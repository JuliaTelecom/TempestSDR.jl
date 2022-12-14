export VideoMode 
export find_closest_configuration
export find_configuration

struct VideoMode 
    width::Int 
    height::Int 
    refresh::Float64
end


const allVideoConfigurations = Dict{String,VideoMode}(
                                         "PAL TV" =>                            VideoMode( 576 , 625 , 25),
                                         "640x400 @ 85Hz"=>VideoMode( 832 , 445 , 85),
                                         "720x400 @ 85Hz"=>VideoMode( 936 , 446 , 85),
                                         "640x480 @ 60Hz"=>VideoMode( 800 , 525 , 60),
                                         "640x480 @ 100Hz"=>VideoMode( 848 , 509 , 100),
                                         "640x480 @ 72Hz"=>VideoMode( 832 , 520 , 72),
                                         "640x480 @ 75Hz"=>VideoMode( 840 , 500 , 75),
                                         "640x480 @ 85Hz"=>VideoMode( 832 , 509 , 85),
                                         "768x576 @ 60 Hz"=>VideoMode( 976 , 597 , 60),
                                         "768x576 @ 72 Hz"=>VideoMode( 992 , 601 , 72),
                                         "768x576 @ 75 Hz"=>VideoMode( 1008, 602 , 75),
                                         "768x576 @ 85 Hz"=>VideoMode( 1008, 605 , 85),
                                         "768x576 @ 100 Hz"=>VideoMode( 1024, 611 , 100),
                                         "800x600 @ 56Hz"   =>VideoMode( 1024, 625 , 56),
                                         "800x600 @ 60Hz"   =>VideoMode( 1056, 628 , 60),
                                         "800x600 @ 72Hz"   =>VideoMode( 1040, 666 , 72),
                                         "800x600 @ 75Hz"   =>VideoMode( 1056, 625 , 75),
                                         "800x600 @ 85Hz"   =>VideoMode( 1048, 631 , 85),
                                         "800x600 @ 100Hz"  =>VideoMode( 1072, 636 , 100),
                                         "1024x600 @ 60 Hz" =>VideoMode( 1312, 622 , 60),
                                         "1024x768i @ 43Hz" =>VideoMode( 1264, 817 , 43),
                                         "1024x768 @ 60Hz"  =>VideoMode( 1344, 806 , 60),
                                         "1024x768 @ 70Hz"  =>VideoMode( 1328, 806 , 70),
                                         "1024x768 @ 75Hz"  =>VideoMode( 1312, 800 , 75),
                                         "1024x768 @ 85Hz"  =>VideoMode( 1376, 808 , 85),
                                         "1024x768 @ 100Hz" =>VideoMode( 1392, 814 , 100),
                                         "1024x768 @ 120Hz" =>VideoMode( 1408, 823 , 120),
                                         "1152x864 @ 60Hz"  =>VideoMode( 1520, 895 , 60),
                                         "1152x864 @ 75Hz"  =>VideoMode( 1600, 900 , 75),
                                         "1152x864 @ 85Hz"  =>VideoMode( 1552, 907 , 85),
                                         "1152x864 @ 100Hz" =>VideoMode( 1568, 915 , 100),
                                         "1280x768 @ 60 Hz" =>VideoMode( 1680, 795 , 60),
                                         "1280x800 @ 60 Hz" =>VideoMode( 1680, 828 , 60),
                                         "1280x960 @ 60Hz"  =>VideoMode( 1800, 1000, 60),
                                         "1280x960 @ 75Hz"  =>VideoMode( 1728, 1002, 75),
                                         "1280x960 @ 85Hz"  =>VideoMode( 1728, 1011, 85),
                                         "1280x960 @ 100Hz" =>VideoMode( 1760, 1017, 100),
                                         "1280x1024 @ 60Hz" =>VideoMode( 1688, 1066, 60),
                                         "1280x1024 @ 75Hz" =>VideoMode( 1688, 1066, 75),
                                         "1280x1024 @ 85Hz" =>VideoMode( 1728, 1072, 85),
                                         "1280x1024 @ 100Hz"=>VideoMode( 1760, 1085, 100),
                                         "1280x1024 @ 120Hz"=>VideoMode( 1776, 1097, 120),
                                         "1368x768 @ 60 Hz" =>VideoMode( 1800, 795 , 60),
                                         "1400x1050 @ 60Hz" =>VideoMode( 1880, 1082, 60),
                                         "1400x1050 @ 72 Hz"=>VideoMode( 1896, 1094, 72),
                                         "1400x1050 @ 75 Hz"=>VideoMode( 1896, 1096, 75),
                                         "1400x1050 @ 85 Hz"=>VideoMode( 1912, 1103, 85),
                                         "1400x1050 @ 100 Hz"=>VideoMode( 1928, 1112, 100),
                                         "1440x900 @ 60 Hz" =>VideoMode( 1904, 932 , 60),
                                         "1440x1050 @ 60 Hz"=>VideoMode( 1936, 1087, 60),
                                         "1600x1000 @ 60Hz" =>VideoMode( 2144, 1035, 60),
                                         "1600x1000 @ 75Hz" =>VideoMode( 2160, 1044, 75),
                                         "1600x1000 @ 85Hz" =>VideoMode( 2176, 1050, 85),
                                         "1600x1000 @ 100Hz"=>VideoMode( 2192, 1059, 100),
                                         "1600x1024 @ 60Hz" =>VideoMode( 2144, 1060, 60),
                                         "1600x1024 @ 75Hz" =>VideoMode( 2176, 1069, 75),
                                         "1600x1024 @ 76Hz" =>VideoMode( 2096, 1070, 76),
                                         "1600x1024 @ 85Hz" =>VideoMode( 2176, 1075, 85),
                                         "1600x1200 @ 60Hz" =>VideoMode( 2160, 1250, 60),
                                         "1600x1200 @ 65Hz" =>VideoMode( 2160, 1250, 65),
                                         "1600x1200 @ 70Hz" =>VideoMode( 2160, 1250, 70),
                                         "1600x1200 @ 75Hz" =>VideoMode( 2160, 1250, 75),
                                         "1600x1200 @ 85Hz" =>VideoMode( 2160, 1250, 85),
                                         "1600x1200 @ 100 Hz"=>VideoMode( 2208, 1271, 100),
                                         "1680x1050 @ 60Hz (reduced blanking)"=>VideoMode( 1840, 1080, 60),
                                         "1680x1050 @ 60Hz (non-interlaced)"=>VideoMode( 2240, 1089, 60),
                                         "1680x1050 @ 60 Hz"=>VideoMode( 2256, 1087, 60),
                                         "1792x1344 @ 60Hz" =>VideoMode( 2448, 1394, 60),
                                         "1792x1344 @ 75Hz" =>VideoMode( 2456, 1417, 75),
                                         "1856x1392 @ 60Hz" =>VideoMode( 2528, 1439, 60),
                                         "1856x1392 @ 75Hz" =>VideoMode( 2560, 1500, 75),
                                         "1920x1080 @ 60Hz" =>VideoMode( 2576, 1125, 60),
                                         "1920x1080 @ 75Hz" =>VideoMode( 2608, 1126, 75),
                                         "1920x1200 @ 60Hz" =>VideoMode( 2592, 1242, 60),
                                         "1920x1200 @ 75Hz" =>VideoMode( 2624, 1253, 75),
                                         "1920x1440 @ 60Hz" =>VideoMode( 2600, 1500, 60),
                                         "1920x1440 @ 75Hz" =>VideoMode( 2640, 1500, 75),
                                         "1920x2400 @ 25Hz" =>VideoMode( 2048, 2434, 25),
                                         "1920x2400 @ 30Hz" =>VideoMode( 2044, 2434, 30),
                                         "2048x1536 @ 60Hz" =>VideoMode( 2800, 1589, 60)
)



""" Internal function to get the best configuration based on input line number and current dict (the initial dict or a filtered one)
"""
function _find_closest_configuration(y_t::Number,dict::Dict{String,VideoMode})
    # --- Find minimum in dictionnary 
    vv,_ = findmin([abs2.(Float64(y_t) .- k.height) for k in values(dict)])
    # --- filter the dicitonnary based on this value 
    subdict = filter( k-> (abs2.(Float64(y_t) .- k[2].height) .== vv), dict)
    if length(subdict) > 1 
        @warn "Several configurations are valid for y_t=$y_t and refresh rate $(get_refresh_rates(dict))" 
    end
    return subdict
end

""" Returns the closest known configuration of type `VideoMode` based on the estimated height `y_t` obtained from autocorrelation and the refresh rate `r`
Returns the name of the configuration and its associated configuration. The latter is a `VideoMode` configuration with the fields `width` `height` and the refesh rate `rate` 

example 
find_closest_configuration(1280,60) # find the configuration for y_t 1280 and 60Hz
("1024x600 @ 60 Hz", VideoMode(1312, 622, 60))
"""
function find_closest_configuration(y_t::Number,r::Number)
    allRates = get_refresh_rates(allVideoConfigurations) 
    _,_idx = findmin( abs2.(r .- allRates))
    chosenRate = allRates[_idx]
    subDict = filter(k-> k[2].refresh == chosenRate,allVideoConfigurations)
    return _find_closest_configuration(y_t,subDict)

end

""" Returns all the supported refresh rates for the given configuration dictionnary
"""
function get_refresh_rates(subdict)
    return unique([k[2].refresh for k in subdict])
end


""" Returns the String configuration associated to the proposed allVideoConfigurations
find_configuration(VideoMode(2592,1242,60)) = "1920x1200 @ 60"
"""
function find_configuration(video::VideoMode)
    for k in keys(allVideoConfigurations)
        if allVideoConfigurations[k] == video 
            return k 
        end 
    end 
end

