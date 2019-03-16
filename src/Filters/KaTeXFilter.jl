using NodeJS

const nodepath = normpath(joinpath(@__DIR__, "..","..", "deps/"))

struct ResolveKaTeX
    mathstr :: String
    display :: Bool
end
const math_resolve_dict = Dict{Tuple{String, Bool}, Union{Nothing, String}}()

function JSON.lower(R::ResolveKaTeX)
    math_resolve_dict[(R.mathstr, R.bool)]
end
 
# Instead of running many processes to parse each expression, I should use the ResolveMe trick to first collect
# all the unparsed expressions, then parse them all at once in one call to node (caching the results as now), and then
# resolve them upon deserialization.

function resolve_math!()
    # testdict = Dict(("abc", true) => nothing, ("bcf", false) => nothing)
    path = joinpath(nodepath, "parsemath.js")
    out = communicate(Cmd(`$(nodejs_cmd()) $path`; dir=nodepath),                                 input=JSON.json(math_resolve_dict)).stdout
    math_resolve_dict = JSON.parse(out)
    # return out
end



"""
Remove unicode characters (via `to_latex`), then render to KaTeX via node.

    katex_math(content) -> RawInline
"""
function katex_math(mathstr, display)
    val = get!(math_resolve_dict, (mathstr, display), nothing)
    isnothing(val) ? ResolveKaTeX(mathstr, display) : val
end



function KaTeXFilter(tag, content, format, meta)
    if tag == "Math"
        mathtype_dict, mathstr = content
        display = mathtype_dict["t"] == "DisplayMath"
        rendered_str = katex_math(mathstr, display)
        return PandocFilters.RawInline("html", rendered_str)
    end
    return nothing
end
