
""" Julia function to read Float32 files 
"""
function readComplexBinary32(file::String)
    samps_per_bytes = 4  # Float32 format 
        # --- Reading file as it is 
    nbSeg = filesize(file) ÷ samps_per_bytes
    y = Array{Float32}(undef, nbSeg);
    read!(file,y)
    # --- Always output a ComplexF32 to ensure type stability
    z = Float32.(y[1:2:end]) + 1im*Float32.(y[2:2:end])
    return z
end

""" Julia function to write file to Float64
"""
function writeComplexBinary64(x::Array{Complex{Float32}},fileID::String) where T
    # --- From Float64 to Float32
    sigTmp = zeros(Float64,2*length(x));
    sigTmp[1:2:end] = convert(Array{Float64},real(x));
    sigTmp[2:2:end] = convert(Array{Float64},imag(x));
    # --- Write data
    out =  open(fileID,"w")
    write(out,sigTmp);
    close(out)
end


""" Convert the .dat file to a .dat64 for numpy 
"""
function convert_dat_file_to_64(filename)
    baseName = string(split(filename,".dat")[1])
    newName = "$(baseName)_64.dat"
    arr = readComplexBinary32(filename) 
    writeComplexBinary64(arr,newName)
end



function convert_folder(dir::String)
    for file in readdir(dir)
        if occursin(".dat",file)
            @info "Convert file $file to 64 complex binary format"
            convert_dat_file_to_64(file)
        end 
    end
end
