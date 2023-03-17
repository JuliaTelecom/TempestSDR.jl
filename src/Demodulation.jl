


"""
Apply FM demodulation to the input signal
It applies Arg(sig[n+1] sig*[n]) where * stands for complex conjugate

Syntax
out = fmDemod(sig)

Input parameters
- sig : Input signal (expected to be complex Vector of type T)

Output parameters
- out : Demodulated signal (T Vector)
"""
function fmDemod(sig::Array{Complex{T}}) where T
    out = zeros(T,length(sig));
    @inbounds @simd for n ∈ (1:length(sig)-1)
        out[n+1] = angle(sig[n+1]*conj(sig[n]));
    end
    return out;
end


function amDemod(sig::Array{Complex{T}}) where T
    return abs.(sig)
end


function invert_amDemod(sig::Array{Complex{T}}) where T
    dd =  abs.(sig)
    dd .= dd ./ maximum(dd)
    return (1 .- dd)
end

