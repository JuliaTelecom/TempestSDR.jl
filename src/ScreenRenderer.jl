module ScreenRenderer
# Module to display the exfiltred screen in a given GUI or in Terminal 

# ----------------------------------------------------
# --- Dependencies 
# ---------------------------------------------------- 
import Base:close  #FIXME necessary here ?
using ImageInTerminal
using Images, ImageView
using Gtk
using Makie,GLMakie

# ----------------------------------------------------
# --- Structures 
# ---------------------------------------------------- 
# Define abstract container 
abstract type AbstractScreenRenderer end


# ----------------------------------------------------
# --- Exportation 
# ---------------------------------------------------- 
export AbstractScreenRenderer 
export initScreenRenderer 
export displayScreen! 
export displayScreen_vsync! 
export close 

# ----------------------------------------------------
# --- Utils 
# ---------------------------------------------------- 
""" Convert the input image with levels between 0 and 1 
"""
function fullScale!(mat)
    mmax = maximum(mat)
    mmin = minimum(mat)
    return (mat .- mmin) / (mmax  - mmin)
end

# ----------------------------------------------------
# --- Terminal Renderer
# ---------------------------------------------------- 
# Structure 
struct TerminalRendererScreen <: AbstractScreenRenderer
end 
# Display 
""" Display the extracted image in the terminal 
"""
function displayScreen!(p::TerminalRendererScreen,img)
    println("\33[H")
    image = fullScale!(img)
    display(colorview(Gray,image))
    return nothing
end
# Close
function close(p::TerminalRendererScreen)
end

# ----------------------------------------------------
# --- Gtk renderer 
# ---------------------------------------------------- 
# Structure 
struct GtkRendererScreen <: AbstractScreenRenderer 
    p::AbstractDict
    function GtkRendererScreen(height,width)
        mat = zeros(height,width)
        fullScale!(mat)
        guidict = ImageView.imshow(mat)
        new(guidict)
    end
end 
# Renderer 
function displayScreen!(p::GtkRendererScreen,img)
    canvas = p.p["gui"]["canvas"] 
    img2 = fullScale!(img)
    imshow(canvas,img2)
    sleep(0.1) 
    yield()
    return nothing
end 
# Close 
function close(p::GtkRendererScreen)
    ImageView.closeall()
end



# ----------------------------------------------------
# --- Makie rendering 
# ---------------------------------------------------- 
# Structure 
mutable struct MakieRendererScreen <: AbstractScreenRenderer
    figure::Any 
    ax::Any
    plot::Any
    function MakieRendererScreen(height,width)
        figure = (; resolution=(800,600))
        m = randn(Float32,height,width)
        figure, ax, plot_obj = heatmap(m, colorrange=(0, 1),colormap="Greys",figure=figure)
        display(figure)
        new(figure,ax,plot_obj)
    end
end
function displayScreen!(b::MakieRendererScreen,img)
    img2 = abs.(1 .-fullScale!(img))
    b.plot[1] = img2
    return nothing
end
function close(b::MakieRendererScreen)
    GLMakie.destroy!(GLMakie.global_gl_screen())
end

# ----------------------------------------------------
# --- Common methods and dispatch 
# ---------------------------------------------------- 
""" Create the GUI and export the canvas that will be updated 
"""
function initScreenRenderer(renderer::Symbol,nbLines,nbColumn)::AbstractScreenRenderer
    if renderer == :terminal
        return TerminalRendererScreen()
    elseif renderer == :gtk 
        return GtkRendererScreen(nbLines,nbColumn)
    elseif renderer == :makie 
        return MakieRendererScreen(nbLines,nbColumn)
    else 
        @error "Unable to init screen renderer: $renderer is an unknown backend"
    end
end

""" Display the extracted image in the terminal. It also print in white the vertical lines and horizontal lines obtained with vsync.
"""
function displayScreen_vsync!(p::AbstractScreenRenderer,image,y_sync,x_sync)
    image = fullScale!(image)
    image[(y_sync) .+ (-10:10),:] .= 1
    image[:,(x_sync) .+ (-10:10)] .= 1
    displayScreen!(p,image)
end
end
