using LaTeX_Entities, StrTables

const LaTeX_Table = LaTeX_Entities.default

function to_latex(char::AbstractChar)
    possibilities = StrTables.matchchar(LaTeX_Table, char)
    isempty(possibilities) && return String(char)
    if length(possibilities) > 1
        @warn "Ambiguity in latexing character" char possibilities
        return "\\" * possibilities[1]
    end
    "\\" * possibilities[]
end

@inline function to_latex(str::AbstractString)
    outstr = ""
    for c in str
        if isascii(c)
            outstr = outstr*c
        else
            outstr = outstr*to_latex(c)
        end
    end
    return outstr
end

# The filter

function unicode_to_latex(tag, content, meta, format)
    if tag == "Math"
        mathtypedict, str = content
        outstr = to_latex(str)
        return PandocFilters.Math(mathtypedict, outstr)
    end
    return nothing
end