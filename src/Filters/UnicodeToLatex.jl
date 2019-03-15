using LaTeX_Entities, StrTables

const LaTeX_Table = LaTeX_Entities.default

function to_latex_char(char::AbstractChar)
    possibilities = StrTables.matchchar(LaTeX_Table, char)
    isempty(possibilities) && return String(char)
    if length(possibilities) > 1
        @warn "Ambiguity in latexing character" char possibilities
        return "\\" * possibilities[1]
    end
    "\\" * possibilities[]
end

"""
A caching function to replace unicode by latex commands.
"""
const to_latex = DictCache{String, String}(
    str::String -> begin
        outstr = ""
        for c in str
            if isascii(c)
                outstr = outstr*c
            else
                outstr = outstr*to_latex_char(c)
            end
        end
        return outstr
    end
)

"""
Filter to walk the Pandoc AST and replace unicode characters in LaTeX math environments with their corresponding LaTeX commands. Hopefully this is simpler and more robust than trying to get xelatex and katex to both fully cooperate.

    unicode_to_latex(tag, content, meta, format)
"""
function unicode_to_latex(tag, content, meta, format)
    if tag == "Math"
        mathtypedict, str = content
        outstr = to_latex(str)
        return PandocFilters.Math(mathtypedict, outstr)
    end
    return nothing
end