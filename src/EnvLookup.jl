@enum Access COUNT DATA
@enum Names SHORT LONG

struct EnvsLookup{K1, K2, T}
    keys :: Vector{Tuple{K1, K2}}
    count :: Vector{Int}
    data :: Vector{T}
    longname_lookup :: Dict{K1, Int}
    shortname_lookup :: Dict{K2, Int}
    function EnvsLookup{K1, K2, T}(keys:: Vector{Tuple{K1, K2}}) where {K1, K2, T}
        longname_lookup = Dict{K1, Int}()
        shortname_lookup = Dict{K2, Int}()
        for i = eachindex(keys)
            a, b = keys[i]
            longname_lookup[a] = i
            shortname_lookup[b] = i
        end

        n = length(keys)
        count = zeros(Int, n)
        data = [T() for _ in 1:n]
        new(keys, count, data, longname_lookup, shortname_lookup)
    end
end

function _getidx(D::EnvsLookup, key, whichname :: Names)
    whichname == LONG ? D.longname_lookup[key] : D.shortname_lookup[key]
end

function Base.getindex(D::EnvsLookup{K1, K2, T}, (key, whichname)::Tuple{<:Union{K1, K2}, Names}, whichdata :: Access ) where {K1, K2, T}
    i = _getidx(D, key, whichname)
    whichdata == COUNT ?  D.count[i] : D.data[i]
end

function Base.setindex!(D::EnvsLookup{K1, K2, T}, value, (key, whichname)::Tuple{<:Union{K1, K2}, Names}, whichdata :: Access) where {K1, K2, T}
    i = _getidx(D, key, whichname)
    if whichdata == COUNT
        D.count[i] = value
    else
        D.data[i] = value
    end
end

function other_name(D::EnvsLookup, key, whichname :: Names)
    if whichname == LONG
        i = D.longname_lookup[key]
        return D.keys[i][2]
    else
        i = D.shortname_lookup[key]
        return D.keys[i][1]

    end
end

function reset!(D::EnvsLookup{K1, K2, T}) where {K1, K2, T}
    n = length(D.keys)
    D.count .= 0
    D.data .= [T() for _ in 1:n]
    nothing
end