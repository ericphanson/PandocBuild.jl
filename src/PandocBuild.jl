module PandocBuild

using PandocFilters, JSON

using Logging

export build, WEB, TEX, PDF, AST, MD, ALL

struct ProcessException <: Exception
    code :: Int
    stderr :: String
 end


include("filters.jl")

# https://discourse.julialang.org/t/collecting-all-output-from-shell-commands/15592/7
function communicate(cmd::Cmd; input = nothing)
    inp = Pipe()
    out = Pipe()
    err = Pipe()

    process = run(pipeline(cmd, stdin=inp, stdout=out, stderr=err), wait=false)
    close(out.in)
    close(err.in)

    stdout = @async String(read(out))
    stderr = @async String(read(err))

    if input !== nothing
        if input isa AbstractString
            print(inp, input)
        elseif input isa AbstractDict
            throw(ArgumentError("input isa AbstractDict"))
        else
            write(process, input)
        end
    end

    close(inp)
    wait(process)
    return (
        stdout = fetch(stdout),
        stderr = fetch(stderr),
        code = process.exitcode
    )
end



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


macro timed_task(name, expr)
    quote

        local n = $name
        try
            local val, t, _ = Base.@timed $(esc(expr))
            @info "$n finished ($(round(t,digits=3))s)"
            val === nothing ? true : val
        catch E
            @error "$n failed" exception=E
            false
        end
    end
end

@enum BuildTargets WEB TEX PDF AST MD ALL

function normalize_targets(targets, openpdf)
    if targets isa AbstractSet
        # done
    elseif targets isa AbstractVector
        targets = Set(targets)
    else
        targets = Set([targets])
    end

    eltype(targets) == BuildTargets || throw(ArgumentError("targets must be a vector or set of BuildTargets"))

    if ALL in targets
        return Set(instances(BuildTargets))
    end

    if openpdf
        push!(targets, PDF)
    end

    if PDF in targets
        push!(targets, TEX)
    end
    return targets
end


function build(dir; filename="thesis", targets = Set([WEB]), openpdf = false)
    
    targets = normalize_targets(targets, openpdf)

    pdf_viewer = "/Applications/Skim.app/Contents/MacOS/Skim"
    src = get_dir("src"; basedir=dir)
    buildtools = joinpath(@__DIR__, "deps")
    outputs = get_dir("outputs"; create=true, basedir=dir)
    tex_aux = get_dir(joinpath("outputs","tex_aux"); create=true, basedir=dir)
    tex_file = joinpath(tex_aux, "$filename.tex")

    # Slow!!
    filters = [
                # "pandoc-unicode-math",
                # get_file(joinpath(buildtools, "pandocfilters", "examples", "theorem.py")),
                # "pandoc-crossref"
              ]

    # these could be combined into 2 total passes for speed,
    # but are kept separate for clarity, for now.
    julia_filters = [ unicode_to_latex, thmfilter, resolver ]
              
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
    
    reset!(envs)

    t = @elapsed @sync begin

        pandoc_str = @timed_task "Get AST, apply filters" begin
            out = communicate(`pandoc $src/$filename.md -f $pandoc_from --filter=$filters -t json`)
            out.code == 0 || throw(ProcessException(out.code, out.stderr))
            
            pandoc_AST = JSON.parse(out.stdout);
            AST_filter!(pandoc_AST, julia_filters);
            JSON.json(pandoc_AST)
        end

        if AST in targets
            @timed_task "write json" begin
                open("$outputs/$filename.json", "w") do f
                    print(f, pandoc_str)
                end
            end
        end
        if TEX in targets
            mktex = @async let
                        @timed_task "tex" begin
                            out = communicate(`pandoc -f json -s -t latex -o $tex_file`; input = pandoc_str)
                            out.code == 0 || throw(ProcessException(out.code, out.stderr))
                            # run(`pandoc $src/$filename.md -f $pandoc_from --filter=$filters -s -t latex -o $tex_file`)
                        end
                    end
        end
       
        if MD in targets
            mkdown = @async let
                        @timed_task "tex" begin
                            out = communicate(`pandoc -f json -s -t markdown -o $outputs/$filename.md`; input = pandoc_str)
                            out.code == 0 || throw(ProcessException(out.code, out.stderr))
                            # run(`pandoc $src/$filename.md -f $pandoc_from --filter=$filters -s -t latex -o $tex_file`)
                        end
                    end
        end


        if WEB in targets
            mkhtml = @async let
                    @timed_task "html" begin
                    out = communicate(`pandoc -f json -s  -t html --katex -o $outputs/$filename.html`; input = pandoc_str)
                    out.code == 0 || throw(ProcessException(out.code, out.stderr))

                        # run(`pandoc $src/$filename.md -f $pandoc_from --filter=$filters -s  -t html --katex -o $outputs/$filename.html`)
                    end
                end
        end

        if PDF in targets
            mkpdf = @async let
                        wait(mktex)
                        @timed_task "pdf" begin
                            run(pipeline(`latexmk $tex_file -pdf -cd -silent`, stdout=devnull, stderr=devnull))
                            cp(joinpath(tex_aux, "$filename.pdf"), joinpath(outputs, "$filename.pdf"); force=true)
                        end 
                    end
        
        checkerrors = @async let
                    wait(mkpdf)
                        @timed_task "rubber-info" begin
                            rubber_out = cd(tex_aux) do
                                    read(`rubber-info $(relpath(tex_file))`, String)
                            end
                            for line in split(rubber_out, "\n")
                                if line != ""
                                    @info line
                                    # write(stdout, "[rubber-info]: " * line * "\n")
                                end
                            end
                        end
                    end
        end

        if openpdf
        do_openpdf = @async let
                    wait(mkpdf)
                    @timed_task "open pdf" run(pipeline(pipeline(`echo $skim_script`, `osascript`), stdout=devnull))
                end
        end


        @info "Launched tasks"
    end

    @info "Finished all tasks ($(round(t,digits=3))s)"

end

end # module
