using NodeJS

const nodepath = normpath(joinpath(@__DIR__, "..","..", "deps/"))

# Instead of running many processes to parse each expression, I should use the ResolveMe trick to first collect
# all the unparsed expressions, then parse them all at once in one call to node (caching the results as now), and then
# resolve them upon deserialization.
"""
Remove unicode characters (via `to_latex`), then render to KaTeX via node.

    katex_math(content) -> RawInline
"""
const katex_math = DictCache{Tuple{String, Bool}, String}(
 ((mathstr, display),) -> begin
        display_str = display ? "true" : "false"
        mathstr = strip(to_latex(mathstr))
        str =   raw"""var katex = require("katex");
                    var str = katex.renderToString(String.raw""" * "\`" * mathstr * "\`" *
                raw""", { displayMode: """ * display_str *
                raw""" });
                    process.stdout.write(str);
                """
        
        out = communicate(Cmd(`$(nodejs_cmd())`; dir=nodepath); input=str)   
        rendered_str = out.stdout
        return rendered_str
    end)



function KaTeXFilter(tag, content, format, meta)
    if tag == "Math"
        mathtype_dict, mathstr = content
        display = mathtype_dict["t"] == "DisplayMath"
        rendered_str = katex_math(mathstr, display)
        return PandocFilters.RawInline("html", rendered_str)
    end
    return nothing
end
