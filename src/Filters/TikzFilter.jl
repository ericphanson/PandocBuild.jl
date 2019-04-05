# Port of https://github.com/jgm/pandocfilters/blob/master/examples/tikz.py

using PandocFilters: Image, Para
const tikz_tasks = Task[]

const strict = Ref(false)
macro timed_task(name, expr)
    quote
        local n = $(esc(name))
        try
            local val, t, _ = Base.@timed $(esc(expr))
            @info "$n finished ($(round(t,digits=3))s)"
            val
        catch E
            @error "$n failed" exception=E
            if strict[]
                rethrow(E)
            end
            E
        end
    end
end

function tikz2image(tikz_src, filetype, outfile)
    doc_str = raw"""
    \documentclass{standalone}
    \usepackage{tikz}
    \begin{document}
                """ * tikz_src * "\n\\end{document}"
    
    mktikz = @async let
        task_str = string("tikz-", hash(tikz_src),".",filetype)
        @timed_task task_str begin
            mktempdir() do dir
                    out = communicate(Cmd(`pdflatex -jobname=tikz -output-directory $dir`; dir=dir); input = doc_str)
                    tikzpdf = joinpath(dir, "tikz.pdf")
                    isfile(tikzpdf) || begin
                    println(readdir())
                        @error "pdflatex didn't seem to make tikz.pdf" pwd() readdir()
                    end
                    if filetype == "pdf"
                        mv("$tikzpdf", "$outfile.$filetype")
                    elseif filetype == "svg"
                        communicate(`pdf2svg $tikzpdf $outfile.$filetype`)
                    else
                        communicate(`convert $tikzpdf $outfile.$filetype`)
                    end
            end
        end
    push!(tikz_tasks, mktikz)
    end
end

"""
Most of a filter; can be used as a closure:

(tag, content, format, meta) -> tikzfilter(tag, content, format, meta, imgdir)

After running, wait.(tikz_tasks) should be used before finishing to make sure all the images are generated.

"""
function tikzfilter(tag, content, format, meta, imgdir = joinpath(pwd(), "images"), rel_imgdir = nothing)
    if tag == "RawBlock"
        fmt, code = content
        if fmt == "latex" 
            matches = match(r"\\begin{tikzpicture}", code)
            isnothing(matches) && return nothing
            filetype = format == "latex" ? "pdf" : "svg"
            outfile = joinpath(imgdir,  string(hash(code)))
            src = string(outfile, ".", filetype)
            if !isfile(src)
                tikz2image(code, filetype, outfile)
            end
            if !isnothing(rel_imgdir)
                src = joinpath(rel_imgdir,  string(hash(code), ".", filetype))
            end
            return Para([Image(["", [], []], [], [src, ""])])
        end
            
    end

end