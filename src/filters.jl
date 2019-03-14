include("EnvLookup.jl")
using LaTeX_Entities, StrTables

const LaTeX_Table = LaTeX_Entities.default

function to_latex(char)
    possibilities = StrTables.matchchar(LaTeX_Table, char)
    isempty(possibilities) && return String(char)
    if length(possibilities) > 1
        @warn "Ambiguity in latexing character" char possibilities
        return "\\" * possibilities[1]
    end
    "\\" * possibilities[]
end

const envs = EnvsLookup{Symbol, Symbol, Dict{String, Int}}([
    (:theorem, :thm),
    (:remark, :rem)
    ])


function other_name(key, whichname)
    other_name(envs, key, whichname)
end

    
function thmfilter(tag, content, meta, format)
    if tag == "Div"
        meta, c = content
        id, classes, kvs = meta
        isempty(classes) && return nothing

        longname = Symbol(first(classes))

        envs[(longname, LONG), COUNT] += 1
        envs[(longname, LONG), DATA][id] = envs[(longname, LONG), COUNT]

    end
    return nothing
end

function unicode_to_latex(tag, content, meta, format)
    if tag == "Math"
        mathtypedict, str = content
        outstr = ""
        for c in str
            if isascii(c)
                outstr = outstr*c
            else
                outstr = outstr*to_latex(c)
            end
        end
        return PandocFilters.Math(mathtypedict, outstr)
    end
    return nothing
end

function resolver(tag, content, meta, format)
    if tag == "RawInline"
        f, c = content
        if f == "tex"
            if startswith(c, raw"\Cref{")
                id = c[7:end-1]
                shortname = Symbol(split(id, ":")[1])
                count = envs[(shortname, SHORT), DATA][id]
               
                prefix = uppercasefirst(String(other_name(shortname, SHORT)))

                return PandocFilters.Str("$prefix $count")
                # println("Resolved $prefix $count.")
            end
        end
    end
    return nothing
end