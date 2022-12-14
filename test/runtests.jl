using TempestSDR
using Test

@testset "Binary files" begin
    # Write your tests here.
    
    # Create binary files 
    x32 = randn(ComplexF32,32)
    writeComplexBinary(x32,"test32.dat")
    @test isfile("test32.dat")
        
    x64 = randn(ComplexF64,32)
    writeComplexBinary(x64,"test64.dat")
    @test isfile("test64.dat")

    # Read binary files 
    x̄ = readComplexBinary("test32.dat")
    @test x32 ≈ x̄ 
    x̄ = readComplexBinary("test64.dat")
    @test x64 ≈ x̄ 

    # Cleaning files 
    rm("test64.dat")
    rm("test32.dat")

end


@testset "Configurations" begin 
    # Get the config 
    theConfig = TempestSDR.allVideoConfigurations
    # Tyoe
    @test theConfig isa(Dict) 
    @test theConfig isa Dict{String,TempestSDR.VideoMode}
    # Size 
    @test length(theConfig) > 10 # Not sure that we have all configs but at leat 10
    @test length(theConfig.vals) > 10 
    # Vals 
    @test theConfig.vals isa Vector{TempestSDR.VideoMode}
    for c in theConfig 
        d = find_closest_configuration(c[2].width,c[2].refresh)
        # Testing if the configuration matches what we have 
        # Several config can works so here consider that one is enough
        #any([isSame(k,c) for k in d])
        any([k == c for k in d])
        
        d = find_closest_configuration(c[2].width + 2,c[2].refresh)
        any([k == c for k in d])
    end

end



