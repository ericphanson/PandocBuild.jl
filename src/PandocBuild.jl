module PandocBuild

# build and possible build targets
export build, watch, WEB, TEX, PDF, TEX_AST, WEB_AST, MD, ALL, SLIDES

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

    sout = @async String(read(out))
    serr = @async String(read(err))

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
    @debug "The process" process
    
    @debug "after sleeping $(isnothing(sleep(1)))"  process

    wait(process)
    @debug "after waiting" process
    @debug "the process's stdin and stdout are" sout serr
    so = fetch(sout)
    se = fetch(serr)
    @debug "these have been fetched" so se
    code = process.exitcode

    code == 0 || begin
        @error "Error in communicate" cmd so se
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

@enum BuildTargets WEB TEX PDF WEB_AST TEX_AST MD ALL SLIDES

include("Build_DAG.jl")

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
         union!(targets, Set(instances(BuildTargets)))
    end

    if openpdf
        push!(targets, PDF)
    end

    if PDF in targets
        push!(targets, TEX)
    end

    needTEX = (TEX in targets);
    if WEB in targets || SLIDES in targets || MD in targets
        needHTML = true;
    else
        needHTML = false;
    end
    return targets, needTEX, needHTML
end


# The big build function

function build(dir; filename="thesis", targets = Set([WEB]), openpdf = false)
    targets, needTEX, needHTML = normalize_targets(targets, openpdf)

    pdf_viewer = "/Applications/Skim.app/Contents/MacOS/Skim"
    src = get_dir("src"; basedir=dir)
    deps = normpath(joinpath(@__DIR__, "..", "deps"))
    outputs = get_dir("outputs"; create=true, basedir=dir)

    markdown_extensions = [
        "+fenced_divs",
        "+backtick_code_blocks",
        "+tex_math_single_backslash"
        ]

    function ensure_katex_css()
        katex_deps = joinpath(deps, "katex.min.css")
        katex_dir = joinpath(dir, "katex.min.css")
        katex_outputs = joinpath(outputs, "katex.min.css")

        if !isfile(katex_dir)
            cp(katex_deps, katex_dir)
        end
        if !isfile(katex_outputs)
            cp(katex_deps,  katex_outputs)
        end
    end

    imgdir = get_dir(joinpath("outputs","images"); create=true, basedir=dir)
               
    skim_script = string(raw"""EOF
                        tell application "Skim"
                        activate
                        open POSIX file """,
                        "\"", joinpath(outputs, filename), ".pdf","\"\n",
                        raw"""
                        end tell
                        EOF""")
    
                        
    reset!(envs) # sneaky reset for the environment numbering (see Filters/Envs.jl)



    make_list = [
        Make("filter tex", 
                inputs = [RAW_TEX_JSON], 
                outputs = [FILT_TEX_JSON], 
                throw=true) do inputs
                    raw_tex_json = inputs[]
                    julia_filters_latex =  [ makeStagedFilter(Dict(
                        "Math" => unicode_to_latex,
                        "RawBlock" => (tag, content, format, meta) -> tikzfilter(tag, content, format, meta, imgdir)
                        )) ]
                    AST_filter!(raw_tex_json, julia_filters_latex, format="latex");
                    [JSON.json(raw_tex_json)]
                end,
        Make("filter web",
                inputs = [RAW_WEB_JSON],
                outputs = [FILT_WEB_JSON],
                throw = true) do inputs
                    raw_web_json = inputs[]
                    julia_filters_html = [ makeStagedFilter(Dict(
                        "Div" => thmfilter, 
                        "RawInline" => resolver, 
                        # use relative image path for html
                        "RawBlock" =>  (tag, content, format, meta) -> tikzfilter(tag, content, format, meta, imgdir, "images"),
                        "Math" => KaTeXFilter
                        ))]
                    AST_filter!(raw_web_json, julia_filters_html, format="html");
                    @debug "Starting `resolve_math!`"
                    resolve_math!()
                    @debug "Finished `resolve_math!`"
                    @debug "Starting JSON.json(raw_web_json)"
                    [JSON.json(raw_web_json)]
                end,
        Make("write web AST",
                inputs = [FILT_WEB_JSON],
                outputs = [WEB_AST]) do inputs
                    filt_web_json = inputs[]
                    open("$outputs/$(filename)_html.json", "w") do f
                        print(f, filt_web_json)
                    end
                    true
                end,
        Make("write tex AST",
                inputs = [FILT_TEX_JSON],
                outputs = [TEX_AST]) do inputs
                    filt_tex_json = inputs[]
                    open("$outputs/$(filename)_latex.json", "w") do f
                        print(f, filt_tex_json)
                    end
                    true
                end,
        Make("Write revealjs slides",
                inputs = [FILT_WEB_JSON],
                outputs = [SLIDES]) do inputs
                    filt_web_json = inputs[]
                    revealjs_deps = joinpath(deps, "reveal.js")
                    revealjs_dir = joinpath(dir, "reveal.js")
                    revealjs_outputs = joinpath(outputs, "reveal.js")
            
                    if !isdir(revealjs_dir)
                        cp(revealjs_deps, revealjs_dir)
                    end
                    if !isdir(revealjs_outputs)
                        cp(revealjs_deps,  revealjs_outputs)
                    end

                    ensure_katex_css()

                    communicate(`pandoc -f json -s -t revealjs -V theme=sunblind --css=katex.min.css -o $outputs/$filename.html`; input = filt_web_json)
                    true
            end,
        Make("Write tex file",
                inputs = [FILT_TEX_JSON],
                outputs = [TEX, TEX_AUX_PATH, TEX_FILE_PATH]) do inputs
                    filt_tex_json = inputs[]
                    tex_aux_path = get_dir(joinpath("outputs","tex_aux"); create=true, basedir=dir)
                    tex_file_path = joinpath(tex_aux_path, "$filename.tex")

                    if SLIDES in targets
                        communicate(`pandoc -f json -s -t beamer -o $tex_file_path`; input = filt_tex_json)
                    else
                        communicate(`pandoc -f json -s -t latex -o $tex_file_path`; input = filt_tex_json)
                    end
                    return [true, tex_aux_path, tex_file_path]
                end,
        Make("Write MD",
                inputs = [FILT_TEX_JSON],
                outputs = [MD]) do inputs
                    filt_tex_json = inputs[]
                    communicate(`pandoc -f json -s -t markdown -o $outputs/$filename.md`; input = filt_tex_json)
                    true
                end,
        Make("Write html",
                inputs = [FILT_WEB_JSON],
                outputs = [WEB]) do inputs
                filt_web_json = inputs[]
                ensure_katex_css()
                # would prefer $katexcss but that messes up relative paths for local webserver
                communicate(`pandoc -f json -s  -t html --css=katex.min.css -o $outputs/$filename.html`; input = filt_web_json)
                true
                end,
        Make("Write PDF",
                inputs = [TEX, TEX_AUX_PATH, TEX_FILE_PATH],
                outputs = [PDF]) do inputs
                    _, tex_aux_path, tex_file_path = inputs
                    wait.(tikz_tasks)
                    run(pipeline(`latexmk $tex_file_path -pdf -cd -silent`, stdout=devnull, stderr=devnull))
                    cp(joinpath(tex_aux_path, "$filename.pdf"), joinpath(outputs, "$filename.pdf"); force=true)
                true
                end,
        Make("Parse tex log",
                inputs = [PDF, TEX_FILE_PATH, TEX_AUX_PATH],
                outputs = [PARSE_TEX_LOG]) do inputs
                    _, tex_file_path, tex_aux_path = inputs
                     # careful: cd changes global state for other tasks.
                    # (https://stackoverflow.com/questions/44571713/julia-language-state-in-async-tasks-current-directory)
                    # since this waits for mkpdf, it runs basically after everything else
                    # so it's probably fine, but maybe this should be changed.
                    rubber_out = cd(tex_aux_path) do
                                read(`rubber-info $(relpath(tex_file_path))`, String)
                                end
                    for line in split(rubber_out, "\n")
                        if line != ""
                            @info line
                            # write(stdout, "[rubber-info]: " * line * "\n")
                        end
                    end
                    true
                    end,
            Make("open PDF", inputs = [PDF], outputs =[]) do inputs
                if openpdf
                    run(pipeline(pipeline(`echo $skim_script`, `osascript`), stdout=devnull))
                end
                openpdf
            end
    ]

    ChannelDict = Dict{Resources, Any}()

    function reset_channel_dict!()
        for j in instances(InternalResources)
            ChannelDict[j] = Channel(1)
        end
        for j in instances(BuildTargets)
            ChannelDict[j] = Channel(1)
        end
    end

    reset_channel_dict!()


    pandoc_from = reduce(*, markdown_extensions; init="markdown")
    out, pandoc_time, _ = @timed communicate(`pandoc $src/$filename.md -f $pandoc_from -t json`)
    @info  "Getting AST from pandoc finished ($(round(pandoc_time,digits=3))s)"

    raw_tex_json = JSON.parse(out.stdout);
    raw_web_json = deepcopy(raw_tex_json)

    put!(ChannelDict[RAW_TEX_JSON], raw_tex_json)
    put!(ChannelDict[RAW_WEB_JSON], raw_web_json)

    t = @elapsed wait.(start_make.(make_list, Ref(ChannelDict)))

    wait.(tikz_tasks)
    empty!(tikz_tasks)

    reset_channel_dict!()

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
