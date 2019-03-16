using NodeJS

const nodepath = normpath(joinpath(@__DIR__, "..","..", "deps/"))

struct ResolveKaTeX
    mathstr :: String
    display :: Bool
end
const math_resolve_dict = Dict{Tuple{String, Bool}, Union{Nothing, String}}();

const to_resolve = Tuple{String, Bool}[];

function JSON.lower(R::ResolveKaTeX)::String
    math_resolve_dict[(R.mathstr, R.bool)]
end
 
# Instead of running many processes to parse each expression, I should use the ResolveMe trick to first collect
# all the unparsed expressions, then parse them all at once in one call to node (caching the results as now), and then
# resolve them upon deserialization.

function resolve_math!()
    global math_resolve_dict
    global to_resolve
    path = joinpath(nodepath, "parsemath.js")
    out = communicate(Cmd(`$(nodejs_cmd()) $path`; dir=nodepath),input=JSON.json(to_resolve)).stdout |> JSON.parse
    for j = eachindex(to_resolve)
        math_resolve_dict[to_resolve[j]] = out[j]
    end
    empty!(to_resolve)
end



"""
Remove unicode characters (via `to_latex`), then render to KaTeX via node.

    katex_math(content) -> RawInline
"""
function katex_math(mathstr, display)
    global math_resolve_dict
    if !haskey(math_resolve_dict,  (mathstr, display))
        push!(to_resolve, (to_latex(mathstr), display))
        math_resolve_dict[(mathstr, display)] = nothing
    end

    val = math_resolve_dict[(mathstr, display)]
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
