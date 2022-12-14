module DatBinaryFiles
# The module helps to manage the .dat file, binary files that are linked to SDR acquisition and load.
# It mainly export readComplexBinary and writeComplexBinary to read a binaruy file and write an array in a binary file

# ----------------------------------------------------
# --- Exportation 
# ---------------------------------------------------- 
export writeComplexBinary
export readComplexBinary

""" 
Write the buffer `x` into the file `fileID` following the .dat format (i.e binary words). The file can be saved in :short format (Int16), :single format (Float32) or :double format (Float64)
"""
function writeComplexBinary(x::Array{Complex{T}},fileID::String,format=:single) where T
    if format == :short 
        sigTmp = zeros(Int16,2*length(x));
        scale = 1 << 14
        sigTmp[1:2:end] = round.(scale*real(x)./maximum(real(x)))
        sigTmp[2:2:end] = round.(scale*imag(x)./maximum(imag(x)))
    else 
        format == :single ? T2 = Float32 : T2=Float64 
        sigTmp = zeros(T2,2*length(x));
        sigTmp[1:2:end] = convert(Array{T2},real(x));
        sigTmp[2:2:end] = convert(Array{T2},imag(x));    
    end
    # --- Write data
    out =  open(fileID,"w")
    write(out,sigTmp);
    close(out)
end


""" Read the binary file file and returns its content as a complex array. 
This function is able to read data with a compatible framework as the Matlab function and the Gnuradio function 

sigId	= readComplexBinary(file,format);
-  Input parameters 
		file	: Name of file [String]
        format  : Format used to save the dat file. Can be :short (In16), :single (Float32) and double (Float64)
-  Output parameters 
		sigId	: Complex data [Array{Complex{Float32}}]. The output is always Float32 to ensure the function is type stable.
        """
function readComplexBinary(file::String,format=:single,nbSeg=nothing)
    # --- Getting number of element to be read
    # Assuming complex element, we have ÷ samps_per_bytes ÷ 2
    if format == :short
        samps_per_bytes = 2 
        T = Int16 
    elseif format == :single 
        samps_per_bytes = 4 
        T = Float32 
    elseif format == :double 
        samps_per_bytes = 8
        T = Float64 
    else 
        @error "Unsupported format for readComplexBinary. Only support :short, :single, :double and got $format"
    end
    # --- Reading file as it is 
    isnothing(nbSeg) && (nbSeg = filesize(file) ÷ samps_per_bytes)
    y = Array{T}(undef, nbSeg);
    read!(file,y)
    # --- Always output a ComplexF32 to ensure type stability
    z = y[1:2:end] + 1im*y[2:2:end]
    return z
end


end
