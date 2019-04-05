using NodeJS, Parameters


const nodepath = normpath(joinpath(@__DIR__, "..","..", "deps/"))

struct ResolveKaTeX
    mathstr :: String
    display :: Bool
end
const math_resolve_dict = Dict{Tuple{String, Bool}, Union{Nothing, NamedTuple{(:rendered_str, :katex_error),Tuple{String,Union{String, Nothing}}}}}();

const to_resolve = Tuple{String, Bool}[];

function JSON.lower(R::ResolveKaTeX)::String
    val = math_resolve_dict[(R.mathstr, R.display)]
    isnothing(val) && begin 
            @error "Math wasn't resolved!" R val
            return ""
    end
    @unpack rendered_str, katex_error = val
    isnothing(katex_error) || @warn("KaTeX error", katex_error)

    return rendered_str 
end

function resolve_math!()
    isempty(to_resolve) && return nothing
    path = joinpath(nodepath, "parsemath.js")
    @debug "Started katex"
    out = communicate(Cmd(`$(nodejs_cmd()) $path`; dir=nodepath), input = JSON.json(to_resolve)).stdout 
    @debug "KaTeX returned"
    out = out |> JSON.parse
    try
        for j = eachindex(to_resolve)
        @debug "at index $j" to_resolve[j]
        katex_error = out[j]["error"]
        rendered_str = out[j]["render"]
        if katex_error != ""
            math_resolve_dict[to_resolve[j]] = (rendered_str = rendered_str, katex_error = katex_error)
        else
            math_resolve_dict[to_resolve[j]] = (rendered_str = rendered_str, katex_error = nothing)
        end
    end
    catch E
        @error E
        rethrow(E)
    end
    empty!(to_resolve)
    @debug "`resolve_math!` done"
    nothing
end


"""
Remove unicode characters (via `to_latex`), then render to KaTeX via node.

    katex_math(content) -> RawInline
"""
function katex_math(mathstr::AbstractString, display::Bool)
    global math_resolve_dict
    if !haskey(math_resolve_dict,  (mathstr, display))
        push!(to_resolve, (mathstr, display))
        math_resolve_dict[(mathstr, display)] = nothing
    end

    val = math_resolve_dict[(mathstr, display)]
    isnothing(val) && return ResolveKaTeX(mathstr, display)

    @unpack rendered_str, katex_error = val
    isnothing(katex_error) || @warn("KaTeX error", katex_error)
    rendered_str
end


function KaTeXFilter(tag, content, format, meta)
    if tag == "Math"
        mathtype_dict, mathstr = content
        mathstr = strip(to_latex(mathstr))
        display = mathtype_dict["t"] == "DisplayMath"
        rendered_str = katex_math(mathstr, display)
        return PandocFilters.RawInline("html", rendered_str)
    end
    return nothing
end
