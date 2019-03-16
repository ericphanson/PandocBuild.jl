module PandocBuild

# build and possible build targets
export build, watch, WEB, TEX, PDF, AST, MD, ALL, SLIDES

# Proccess and logging
using Logging

struct ProcessException <: Exception
    code :: Int
    stderr :: String
 end

 # Modified from
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
    so = fetch(stdout)
    se = fetch(stderr)
    code = process.exitcode

    code == 0 || begin
        @error "Error in communicate" cmd
        throw(ProcessException(code, se))
    end
    return (
        stdout = so,
        stderr = se,
        code = code
    )
end

# Helpers

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


macro timed_task(name, expr)
    quote
        local n = $(esc(name))
        try
            local val, t, _ = Base.@timed $(esc(expr))
            @info "$n finished ($(round(t,digits=3))s)"
            val
        catch E
            @error "$n failed" exception=E
            E
        end
    end
end

macro timed_task_throw(name, expr)
    quote
        local n = $(esc(name))
        local val, t, _ = Base.@timed $(esc(expr))
        @info "$n finished ($(round(t,digits=3))s)"
        val
    end
end

# Filters

using PandocFilters, JSON

# `KaTeXFilter` and `unicode_to_latex` use `DictCache` objects to cache katex rendering and unicode conversion, respectively. I think this should help speed up work on large files, when repeatedly recompiling with few changes. 
# `TikzFilter` has a form of caching; it names files by the hash of the tikz code used to generate them, and doesn't regenerate ones which already exist. That leaves only the theorem numbering filters, which likely can't be memoized or cached easily.
include("Filters/DictCache.jl")
include("Filters/Envs.jl")
include("Filters/UnicodeToLatex.jl")
include("Filters/TikzFilter.jl")
include("Filters/KaTeXFilter.jl")

"""
Many filters do not interact with each other; they act on different elements and often no global information. So it doesn't make sense to walk the AST `n` times to execute `n` filters. We instead group filters into a "staged filter" which walks the AST once, and dispatches various tags to various filters, using a dictionary. We can likely then execute `n` filters using only 1-2 walks of the AST, at the cost of a dictionary lookup.
"""
function makeStagedFilter(filter_dict)
    function f(tag, content, meta, format)
        if haskey(filter_dict, tag)
            return filter_dict[tag](tag, content, meta, format)
        end
        nothing
    end
    return f
end

# Build targets

@enum BuildTargets WEB TEX PDF AST MD ALL SLIDES

function normalize_targets(targets, openpdf)
    if targets isa AbstractSet
        # done
    elseif targets isa AbstractVector
        targets = Set(targets)
    else
        targets = Set([targets])
    end

    eltype(targets) == BuildTargets || throw(ArgumentError("targets must be a single BuiltTargets or a vector or set thereof"))

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


# The big build function

function build(dir; filename="thesis", targets = Set([WEB]), openpdf = false)
    cd(dir)
    targets = normalize_targets(targets, openpdf)

    pdf_viewer = "/Applications/Skim.app/Contents/MacOS/Skim"
    src = get_dir("src"; basedir=dir)
    buildtools = joinpath(@__DIR__, "deps")
    outputs = get_dir("outputs"; create=true, basedir=dir)

    if (SLIDES in targets) || (WEB in targets)
        katex_css = joinpath(dir, "katex.min.css")
        if !isfile(katex_css)
            cp(joinpath(@__DIR__, "..", "deps", "katex.min.css"), katex_css)
            # stupid hack for pandoc relative paths
            cp(joinpath(@__DIR__, "..", "deps", "katex.min.css"),  joinpath(outputs, "katex.min.css"))
        end
    end

    if TEX in targets
        tex_aux = get_dir(joinpath("outputs","tex_aux"); create=true, basedir=dir)
        tex_file = joinpath(tex_aux, "$filename.tex")
    end

    imgdir = get_dir(joinpath("outputs","images"); create=true, basedir=dir)

    # We've done a bit of work (see the `Envs.jl` file) so that both for latex and HTML, we only need to walk the AST once to run all our filters, using this `makeStagedFilter` function.
    julia_filters_latex =   [ makeStagedFilter(Dict(
                                    "Math" => unicode_to_latex,
                                    "RawBlock" => (tag, content, format, meta) -> tikzfilter(tag, content, format, meta, imgdir)
                                    )), 
                            ]
  
    julia_filters_html = [ makeStagedFilter(Dict(
                        "Div" => thmfilter, 
                        "RawInline" => resolver, 
                        # use relative image path for html
                        "RawBlock" =>  (tag, content, format, meta) -> tikzfilter(tag, content, format, meta, imgdir, "images"),
                        "Math" => KaTeXFilter
                        ))]
               
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
    
                        
    reset!(envs) # sneaky reset for the environment numbering (see Filters/Envs.jl)
    pandoc_latex = Channel(1)
    pandoc_html = Channel(1)
    t = @elapsed @sync begin

        out, pandoc_time, _ = @timed communicate(`pandoc $src/$filename.md -f $pandoc_from -t json`)
        @info  "Getting AST from pandoc finished ($(round(pandoc_time,digits=3))s)"
        pandoc_AST_latex = JSON.parse(out.stdout);
        # is deepcopy the fastest way to do this? Is it better to make a non-mutating version of `AST_filter!` and use that?
        pandoc_AST_html = deepcopy(pandoc_AST_latex)

        @async begin
            @timed_task_throw "latex filters" begin
                AST_filter!(pandoc_AST_latex, julia_filters_latex, format="latex");
                put!(pandoc_latex, JSON.json(pandoc_AST_latex))
            end
        end

        @async begin
            @timed_task_throw "html filters" begin
                AST_filter!(pandoc_AST_html, julia_filters_html, format="html");
                @info "starting resolve math"
                resolve_math!()
                @info "finished resolve math"
                put!(pandoc_html, JSON.json(pandoc_AST_html))
            end
        end

        if AST in targets
            @async let
                @timed_task "write json" begin
                    open("$outputs/$(filename)_latex.json", "w") do f
                        print(f, fetch(pandoc_latex))
                    end
                    open("$outputs/$(filename)_html.json", "w") do f
                        print(f, fetch(pandoc_html))
                    end
                end
            end
        end

        if SLIDES in targets
            isdir(joinpath(outputs, "reveal.js")) || throw(error("reveal.js must be in outputs"))
            mkslides = @async let
                @timed_task "slides" begin
                    communicate(`pandoc -f json -s -t revealjs -V theme=sunblind --css=katex.min.css -o $outputs/$filename.html`; input = fetch(pandoc_html))
                end
            end

        end
        if TEX in targets
            mktex = @async let
                        @timed_task "tex" begin
                        if SLIDES in targets
                            communicate(`pandoc -f json -s -t beamer -o $tex_file`; input = fetch(pandoc_latex))
                        else
                            communicate(`pandoc -f json -s -t latex -o $tex_file`; input = fetch(pandoc_latex))
                        end
                        end
                    end
        end
       
        if MD in targets
            mkdown = @async let
                        @timed_task "markdown" begin
                            communicate(`pandoc -f json -s -t markdown -o $outputs/$filename.md`; input = fetch(pandoc_latex))
                        end
                    end
        end


        if WEB in targets
            mkhtml = @async let
                    @timed_task "html" begin
                    # would prefer $katexcss but that messes up relative paths for local webserver
                    communicate(`pandoc -f json -s  -t html --css=katex.min.css -o $outputs/$filename.html`; input = fetch(pandoc_html))
                    end
                end
        end

        if PDF in targets
            mkpdf = @async let
                        wait(mktex)
                        wait.(tikz_tasks)
                        @timed_task "pdf" begin
                            run(pipeline(`latexmk $tex_file -pdf -cd -silent`, stdout=devnull, stderr=devnull))
                            cp(joinpath(tex_aux, "$filename.pdf"), joinpath(outputs, "$filename.pdf"); force=true)
                        end 
                    end
        
        checkerrors = @async let
                    wait(mkpdf)
                        @timed_task "rubber-info" begin
                            # careful: cd changes global state for other tasks.
                            # (https://stackoverflow.com/questions/44571713/julia-language-state-in-async-tasks-current-directory)
                            # since this waits for mkpdf, it runs basically after everything else
                            # so it's probably fine, but maybe this should be changed.
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
    wait.(tikz_tasks)
    empty!(tikz_tasks)
    take!(pandoc_latex)
    take!(pandoc_html)
    @info "Finished all tasks ($(round(t,digits=3))s)"

end


# Watching and rebuilding

using FileWatching

"""
Rerun build when files are changed. Can be started via, e.g.

```julia
watch_task = @async watch(@__DIR__; filename="slides", targets=[SLIDES, MD])
```

and later killed by

```julia
Base.throwto(watch_task, InterruptException())
````
"""
function watch(dir; filename="thesis", targets = Set([WEB]), openpdf = false)
    while true
        src = get_dir("src"; basedir=dir)
        ret = watch_file(joinpath(src,"$filename.md"))
        build(dir; filename=filename, targets=targets, openpdf=openpdf)
        sleep(1)
    end
end

end # module
