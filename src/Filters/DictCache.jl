# A simple memoization structure.

"""
A `DictCache{K,T}(f)` is a replacement for a function `f(x::K)::T` that adds a dictionary-based cache. To treat multi-argument functions, `K` should be a `Tuple` type, and `f` should be written to accept a tuple (possibly by destructuring). These are callable, should be able to be used as a drop-in replacement for `f`.
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