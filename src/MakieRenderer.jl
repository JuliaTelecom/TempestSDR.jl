module MakieRenderer 

using Makie 
using GLMakie
using Images

export MakieRendererScreen
export displayMakieScreen!



mutable struct MakieRendererScreen 
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

function fullScale!(mat)
    mmax = maximum(mat)
    mmin = minimum(mat)
    return (mat .- mmin) / (mmax  - mmin)
end

function displayMakieScreen!(b::MakieRendererScreen,img)
    img2 = abs.(1 .-fullScale!(img))
    b.plot[1] = img2
end

end 
