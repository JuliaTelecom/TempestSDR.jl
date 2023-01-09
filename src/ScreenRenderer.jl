module ScreenRenderer
# Module to display the exfiltred screen in a given GUI or in Terminal 

# ----------------------------------------------------
# --- Dependencies 
# ---------------------------------------------------- 
# For external renderer 
using Images, ImageView
using Gtk
# For terminal renderer 
using ImageInTerminal
#using Sixel

# ----------------------------------------------------
# --- Exportation 
# ---------------------------------------------------- 
export initScreenRenderer 
export displayScreen!
export close_all
export terminal 
export terminal_with_sync

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
    yield()
    #Libc.systemsleep(0.001)
    #reveal(p["gui"]["window"],true)
end


function fullScale!(mat)
    mmax = maximum(mat)
    mmin = minimum(mat)
    return (mat .- mmin) / (mmax  - mmin)
end


import Base.close
function close_all()
    ImageView.closeall()
end


""" Display the extracted image in the terminal 
"""
function terminal(image)
    println("\33[H")
    image = fullScale!(image)
    display(colorview(Gray,image))
end

""" Display the extracted image in the terminal. It also print in white the vertical lines and horizontal lines obtained with vsync.
"""
function terminal_with_sync(image,y_sync,x_sync)
    println("\33[H")
    image = fullScale!(image)
    image[(y_sync) .+ (-10:10),:] .= 1
    image[:,(x_sync) .+ (-10:10)] .= 1
    display(colorview(Gray,image))
end
end
