using Documenter

makedocs(sitename="TempestSDR.jl", 
         format = Documenter.HTML(),
         pages    = Any[
                        "Introduction to TempestSDR.jl"   => "index.md",
                        "Screen eavesdropping context"    => "context.md",
                        "Installation and basic usage"    => "install.md",
                        "GUI explanation"                 => "gui.md",
                        "Using a real SDR"                => "sdr.md",
                        "Precompilation notes"            => "precompilation.md",
                        ],
         );

#makedocs(sitename="My Documentation", format = Documenter.HTML(prettyurls = false))

deploydocs(
           repo = "github.com/JuliaTelecom/TempestSDR.jl",
          )
