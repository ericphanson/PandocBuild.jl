module PandocBuild

export build

function get_dir(dir; create=false, basedir)
    path = joinpath(basedir, dir)

    isdir(path) && return path

    if create
        mkpath(path)
    else
        throw(error("Directory $path not found"))
    end
    path
end

function get_file(file)
    isfile(file) || throw(error("File $file not found"))
    file
end


const buildname = basename(@__FILE__)

function msg(str)
    println(string("[", buildname, "]: "), str)
end

macro timed(name, expr)
    quote

        local n = $name
        # msg("$n started")
        try
            local t = @elapsed $(esc(expr))
            msg("$n finished ($(round(t,digits=3))s)")
            true
        catch E
            msg("$n failed: $E")
            false
        end
    end
end


function build(dir; filename="thesis")
    pdf_viewer = "/Applications/Skim.app/Contents/MacOS/Skim"
    src = get_dir("src"; basedir=dir)
    buildtools = joinpath(@__DIR__, "deps")
    outputs = get_dir("outputs"; create=true, basedir=dir)
    tex_aux = get_dir(joinpath("outputs","tex_aux"); create=true, basedir=dir)
    tex_file = joinpath(tex_aux, "$filename.tex")

    filters = [
                "pandoc-unicode-math",
                # get_file(joinpath(buildtools, "pandocfilters", "examples", "theorem.py")),
                "pandoc-crossref"
              ]
              
    markdown_extensions = [
                "+fenced_divs",
                "+backtick_code_blocks",
                "+tex_math_single_backslash"
                ]

    pandoc_from = reduce(*, markdown_extensions; init="markdown")

    skim_script = string(raw"""EOF
                        tell application "Skim"
                        activate
                        open POSIX file """,
                        "\"", joinpath(outputs, filename), ".pdf","\"\n",
                        raw"""
                        end tell
                        EOF""")
    t = @elapsed @sync begin


        # ps = []
        # open(`pandoc $src/$filename.md -f $pandoc_from --filter=$filters -t json`, "r") do f
        #     push!(ps, run(pipeline(f,`pandoc --from=json -s -t latex -o $tex_file`)))
        #     push!(ps,run(pipeline(f, `pandoc -f json -t html -s --katex  -o $outputs/$filename.html`); wait=false))
        # end
        # mktex = ps[1]
        # wait.(ps)

        # I'd like to have pandoc send the filtered AST to julia, which would then send it to both the html and latex outputs
        # so the filters and markdown parsing is only done once! But it probably doesn't really make much of a difference
        # since the html and latex are fully parallel to each other anyway.
        mktex = @async let
                    @timed "tex" begin
                        run(`pandoc $src/$filename.md -f $pandoc_from --filter=$filters -s -t latex -o $tex_file`)
                    end
                end
        # mkjson = @async let
        #             @timed "json" begin
        #                 run(`pandoc $src/$filename.md -f $pandoc_from -t json -o $outputs/$filename.json`)
        #             end
        #         end

        mkhtml = @async let
                    @timed "html" begin
                        run(`pandoc $src/$filename.md -f $pandoc_from --filter=$filters -s  -t html --katex -o $outputs/$filename.html`)
                    end
                end
        mkpdf = @async let
                    wait(mktex)
                    @timed "pdf" begin
                        run(pipeline(`latexmk $tex_file -pdf -cd -silent`, stdout=devnull, stderr=devnull))
                        cp(joinpath(tex_aux, "$filename.pdf"), joinpath(outputs, "$filename.pdf"); force=true)
                    end 
                end
        checkerrors = @async let
                    wait(mkpdf)
                        @timed "rubber-info" begin
                            rubber_out = cd(tex_aux) do
                                    read(`rubber-info $(relpath(tex_file))`, String)
                            end
                            for line in split(rubber_out, "\n")
                                if line != ""
                                    write(stdout, "[rubber-info]: " * line * "\n")
                                end
                            end
                        end
                    end

        openpdf = @async let
                    wait(mkpdf)
                    @timed "open pdf" run(pipeline(pipeline(`echo $skim_script`, `osascript`), stdout=devnull))
                end


        msg("Launched tasks")
    end

    msg("Finished all tasks ($(round(t,digits=3))s)")

end

end # module
