module PandocBuild

# build and possible build targets
export build, watch,    WEB, WEB_AST, WEB_MD, WEB_SLIDES,
                        TEX, PDF, TEX_AST, TEX_MD, TEX_SLIDES,
                        ALL

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

    wait(process)
    @debug "after waiting" process
    so = fetch(sout)
    se = fetch(serr)
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

@enum BuildTargets WEB WEB_AST WEB_MD WEB_SLIDES TEX PDF TEX_AST TEX_MD TEX_SLIDES ALL OPEN_PDF

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
    if openpdf
        push!(targets, OPEN_PDF)
    end
    return targets
end


# The big build function

function build(dir; filename="thesis", targets = Set([WEB]), openpdf = false)
    targets = normalize_targets(targets, openpdf)
    
    if isempty(targets)
        throw(ArgumentError("No build targets; exiting."))
        return false
    end

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

        fonts_deps = joinpath(deps, "fonts")
        fonts_dir = joinpath(dir, "fonts")
        fonts_outputs = joinpath(outputs, "fonts")

        if !isdir(fonts_dir)
            cp(fonts_deps, fonts_dir)
        end
        if !isdir(fonts_outputs)
            cp(fonts_deps,  fonts_outputs)
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



    all_targets = [ tar for tar in instances(BuildTargets) if (tar !=  ALL) && (tar != OPEN_PDF)]
    if openpdf
        push!(all_targets, OPEN_PDF)
    end

    
    make_list = [
        Make("filter tex", 
                inputs = [RAW_JSON], 
                outputs = [FILT_TEX_JSON], 
                throw=true) do inputs
                    raw_json = inputs[]
                    raw_tex_json = deepcopy(raw_json)
                    julia_filters_latex =  [ makeStagedFilter(Dict(
                        "Math" => unicode_to_latex,
                        "RawBlock" => (tag, content, format, meta) -> tikzfilter(tag, content, format, meta, imgdir)
                        )) ]
                    AST_filter!(raw_tex_json, julia_filters_latex, format="latex");
                    [JSON.json(raw_tex_json)]
                end,
        Make("filter web",
                inputs = [RAW_JSON],
                outputs = [FILT_WEB_JSON],
                throw = true) do inputs
                    raw_json = inputs[]
                    raw_web_json = deepcopy(raw_json)
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
                outputs = [WEB_SLIDES]) do inputs
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

                    if TEX_SLIDES in targets
                        communicate(`pandoc -f json -s -t beamer -o $tex_file_path`; input = filt_tex_json)
                    else
                        communicate(`pandoc -f json -s -t latex -o $tex_file_path`; input = filt_tex_json)
                    end
                    return [true, tex_aux_path, tex_file_path]
                end,
        Make("Write TEX_MD",
                inputs = [FILT_TEX_JSON],
                outputs = [TEX_MD]) do inputs
                    filt_tex_json = inputs[]
                    communicate(`pandoc -f json -s -t markdown -o $outputs/tex_$filename.md`; input = filt_tex_json)
                    true
                end,
        Make("Write WEB_MD",
                inputs = [FILT_WEB_JSON],
                outputs = [WEB_MD]) do inputs
                    filt_web_json = inputs[]
                    communicate(`pandoc -f json -s -t markdown -o $outputs/web_$filename.md`; input = filt_web_json)
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
                        end
                    end
                    true
                    end,
            Make("open PDF", inputs = [PDF], outputs =[OPEN_PDF]) do inputs
                if openpdf
                    run(pipeline(pipeline(`echo $skim_script`, `osascript`), stdout=devnull))
                end
                openpdf
            end,
            Make("all", inputs = all_targets, outputs = [ALL]) do inputs
                true
            end,
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

    # Start getting the AST right away
    start_make(Make("Get AST from pandoc", inputs = [], outputs = [RAW_JSON]) do inputs
        pandoc_from = reduce(*, markdown_extensions; init="markdown")

        out = communicate(`pandoc $src/$filename.md -f $pandoc_from -t json`)
        
        [JSON.parse(out.stdout)]
    end, ChannelDict)
    

    G, build_dag_time, _ = @timed build_DAG(make_list)
    @info  "Building DAG took ($(round(build_dag_time,digits=3))s)"

    do_list, build_do_list_time, _ = @timed get_do_list(G, make_list, targets)
    @info  "Choosing optimal path through DAG took ($(round(build_do_list_time,digits=3))s)"

   

    @debug "Starting do_list"

    task_list = start_make.(do_list, Ref(ChannelDict))
    @debug "constructed task_list" task_list
    t = @elapsed wait.(task_list)

    @debug "waiting for tikz_tasks"
    wait.(tikz_tasks)
    empty!(tikz_tasks)

    reset_channel_dict!()

    @info "Finished all tasks ($(round(t,digits=3))s)"
    return G
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
