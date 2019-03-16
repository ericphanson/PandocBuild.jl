# Custom struct to store and lookup environment information. 
include("EnvLookup.jl")


# Eventually these environment names should be grabbed from the markdown file's metadata,
# and this should be constructed at runtime. Probably pass it as an argument
# to `thmfilter` and `resolver`, then call `AST_filter!` with a closure.
const envs = EnvsLookup{Symbol, Symbol, Dict{String, Int}}([
    (:theorem, :thm),
    (:remark, :rem)
    ])



# Make `envs` implicit for convenience
other_name(key, whichname) = other_name(envs, key, whichname)
isshortname(key) = isshortname(envs, key)
islongname(key) = islongname(envs, key)

struct ResolveCref
    id :: String
    envshortname :: Symbol
end

# The magic: \Cref's get resolved during JSON serialization.
function JSON.lower(R::ResolveCref)
    count = envs[(R.envshortname,SHORT), DATA][R.id]
    prefix = uppercasefirst(String(other_name(R.envshortname, SHORT)))
    "$prefix $count"
end

"""
Filter to walk through the AST, looking for `Div`'s. If such a `Div` has its first class as one of the environments we are tracking (defined in `envs`), we bump up the corresponding count in `envs`. If it has an `id`, we record the number (i.e. the current count) in the dictionary stored in `envs`. Should be followed by `resolver` to make use of these counts.

    thmfilter(tag, content, meta, format)
"""
function thmfilter(tag, content, meta, format)
    if tag == "Div"
        meta, c = content
        id, classes, kvs = meta
        isempty(classes) && return nothing

        longname = Symbol(first(classes))
        islongname(longname) || return nothing

        envs[(longname, LONG), COUNT] += 1

        envs[(longname, LONG), DATA][id] = envs[(longname, LONG), COUNT]

    end
    return nothing
end

"""
Filter to walk through the AST, looking for `\\Cref{}`'s, which live in `RawInline` Pandoc elements. Upon finding one, we try to resolve the `\\Cref{}`, i.e., replace it by e.g. `Theorem 2`. A priori, we need to know what theorem number to point to in order to return a string here. Since we may not have that information yet, we instead put a `ResolveMe` object that gets resolved to the correct string upon JSON serialization.

    resolver(tag, content, meta, format)
"""
function resolver(tag, content, meta, format)
    if tag == "RawInline"
        f, c = content
        if f == "tex"
            if startswith(c, raw"\Cref{")
                id = c[7:end-1]
                shortname = Symbol(split(id, ":")[1])
                return PandocFilters.Str(ResolveCref(id, shortname))
            end
        end
    end
    return nothing
end