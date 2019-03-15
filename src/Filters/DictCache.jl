"""
A simple memoization structure.
"""
struct DictCache{K, T, F}
    dict :: Dict{K,T}
    f :: F
    DictCache{K,T,F}(f) where {K,T,F} = new(Dict{K, T}(), f)
end

DictCache{K, T}(f) where {K,T} = DictCache{K,T,typeof(f)}(f)

function (DC::DictCache)(key...)
    if length(key) == 1
        key = key[1]
    end    
    if haskey(DC.dict, key)
        return DC.dict[key]
    else
        value = DC.f(key)
        DC.dict[key] = value
        return value
    end
end

# # if you're given multiple arguments, DC.f should accept a tuple.
# (DC::DictCache)(key...) = DC(key)