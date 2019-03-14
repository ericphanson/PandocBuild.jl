using NodeJS

const nodepath = normpath(joinpath(@__DIR__, "..","..", "deps/"))

function KaTeXFilter(tag, content, format, meta)
    if tag == "Math"
        mathtype_dict, mathstr = content
        display = mathtype_dict["t"] == "DisplayMath"
        display_str = display ? "true" : "false"
        mathstr = strip(mathstr)
        str =   raw"""var katex = require("katex");
                    var str = katex.renderToString(String.raw""" * "\`" * mathstr * "\`" *
                raw""", { displayMode: """ * display_str *
                raw""" });
                    process.stdout.write(str);
                """
        
        out = communicate(Cmd(`$(nodejs_cmd())`; dir=nodepath); input=str)   
        rendered_str = out.stdout
        return PandocFilters.RawInline("html", rendered_str)
    end
    return nothing
end
