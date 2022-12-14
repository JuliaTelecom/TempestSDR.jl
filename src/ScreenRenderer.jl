module ScreenRenderer
# Module to display the exfiltred screen in a given GUI

# ----------------------------------------------------
# --- Dependencies 
# ---------------------------------------------------- 
using Images, ImageView
using Gtk

# ----------------------------------------------------
# --- Exportation 
# ---------------------------------------------------- 
export initScreenRenderer 
export displayScreen!
export close

# ----------------------------------------------------
# --- Methods
# ---------------------------------------------------- 
""" Create the GUI and export the canvas that will be updated 
"""
function initScreenRenderer(nbLines,nbColumn)
    mat = zeros(nbLines,nbColumn)
    guidict = ImageView.imshow(mat)
    return guidict 
end

function displayScreen!(p,img)
    canvas = p["gui"]["canvas"] 
    fullScale!(img)
    imshow(canvas,img)
    #Gtk.set_gtk_property!(p, :margin_top, 0)
        #@async Gtk.gtk_main()
        #reveal(p, true)
    Gtk.showall(p["gui"]["window"])
    sleep(0.000001)
    #yield()
    #Libc.systemsleep(0.001)
    #reveal(p["gui"]["window"],true)
end


function fullScale!(mat)
    mmax = maximum(mat)
    mmin = minimum(mat)
    mat  = (mat .- mmin) / (mmax  - mmin)
end


import Base.close
function close(win::Dict{String,Any})
    #Gtk.gtk_quit()
    Gtk.destroy(win["gui"]["window"])
end

end
