module ScreenRenderer
# Module to display the exfiltred screen in a given GUI or in Terminal 

# ----------------------------------------------------
# --- Dependencies 
# ---------------------------------------------------- 
import Base:close 
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
export displayScreen
export displayScreen! 
export displayScreen_vsync! 
export close 
#export plotInteractiveCorrelation
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
    axis_image::Any 
    axis_refresh::Any 
    axis_yt::Any
    plot::Any
    function MakieRendererScreen(height,width)
        # --- Define the Grid Layout 
        figure = Figure(backgroundcolor=:lightgrey,resolution=(1800,1200))
        g_im = figure[1:6, 1:2] = GridLayout()
        g_T = figure[7, 1:3] = GridLayout()
        g_Z = figure[8, 1:3] = GridLayout()
        # --- Add a first image
        axIm = Makie.Axis(g_im[1,1])
        m = randn(Float32,height,width)
        plot_obj = _plotHeatmap(axIm,m)
        # --- Display the first lines for correlation 
        axT = Makie.Axis(g_T[1,1])
        delay = 1 : 100
        corr = zeros(Float32,100)
        _plotInteractiveCorrelation(axT,delay,corr,0,:turquoise4)
        # The zoomed correlation 
        axZ = Makie.Axis(g_Z[1,1])
        _plotInteractiveCorrelation(axZ,delay,corr,0,:gold4)
        # Display the image 
        #display(GLMakie.Screen(),figure)
        display(figure)
        # Final constructor
        new(figure,axIm,axT,axZ,plot_obj)
    end
end

function _plotInteractiveCorrelation(axis,delay,corr,select_f=0,color=:gold4) 
    # Empty the axis in case of redrawn 
    empty!(axis)
    # Plot the correlation
    lines!(axis,delay,corr;color)
    # Add a vertical lines for refresh selection
    text!(axis,"r", visible = false)
    vlines!(axis,select_f,color=:tomato,linewidth = 3.00)
end


function _plotHeatmap(axis,image) 
    # Empty the axis in case of redrawn 
    empty!(axis)
    plot_obj = heatmap!(axis,collect(transpose(image)),colormap=Reverse("Greys"),fxaa=false)
    axis.yreversed=true
    return plot_obj
end



function displayScreen!(b::MakieRendererScreen,img)
    #img2 = abs.(1 .-fullScale!(img))
    b.plot[1] = img'
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
    image[(y_sync) .+ (-10:10),:] .= 1'
    image[:,(x_sync) .+ (-10:10)] .= 1
    displayScreen!(p,image)
end



function displayScreen(renderer::Symbol,image) 
    nbLines,nbColumn = size(image) 
    screen = initScreenRenderer(renderer,nbLines,nbColumn)
    displayScreen!(screen,image) 
    return screen 
end


end
