# Port of https://github.com/jgm/pandocfilters/blob/master/examples/tikz.py

using PandocFilters: Image, Para
const tikz_tasks = Task[]

function tikz2image(tikz_src, filetype, outfile)
    doc_str = raw"""
    \documentclass{standalone}
    \usepackage{tikz}
    \begin{document}
                """ * tikz_src * "\n\\end{document}"
    
    mktikz = @async let
        @timed_task "tikz $outfile" begin
            mktempdir() do dir
                    out = communicate(`pdflatex -jobname=tikz -output-directory $dir`; input = doc_str)
                    out.code == 0 || throw(ProcessException(out.code, out.stderr))
                    tikzpdf = joinpath(dir, "tikz.pdf")
                    isfile(tikzpdf) || begin
                    println(readdir())
                        @error "pdflatex didn't seem to make tikz.pdf" pwd() readdir()
                    end
                    if filetype == "pdf"
                        mv("$tikzpdf", "$outfile.$filetype")
                    elseif filetype == "svg"
                        out2 = communicate(`pdf2svg $tikzpdf $outfile.$filetype`)
                        out2.code == 0 || throw(ProcessException(out2.code, out2.stderr))
                    else
                        out2 = communicate(`convert $tikzpdf $outfile.$filetype`)
                        out2.code == 0 || throw(ProcessException(out2.code, out2.stderr))
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
                @info "Started tikz image $src"
            end
            if !isnothing(rel_imgdir)
                src = joinpath(rel_imgdir,  string(hash(code), ".", filetype))
            end
            return Para([Image(["", [], []], [], [src, ""])])


        end
            
    end

end