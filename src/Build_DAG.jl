@enum InternalResources RAW_JSON FILT_TEX_JSON FILT_WEB_JSON TEX_AUX_PATH TEX_FILE_PATH PARSE_TEX_LOG

const Resources = Union{InternalResources, BuildTargets}

using LightGraphs, MetaGraphs



Base.@kwdef struct Make
    f
    name :: String
    inputs :: Vector{Resources}
    outputs :: Vector{Resources}
    throw = true :: Bool
end

Make(f, name ; inputs, outputs,  throw = false) = Make(f=f, name=name, inputs=inputs, outputs=outputs, throw=throw)

struct FailedDepsException <: Exception
    failed_deps
end

function start_make(m::Make, ChannelDict)
    @async begin
        @debug "$(m.name) started to wait for inputs"
        inputs = [ fetch(ChannelDict[i]) for i in m.inputs ]
        @debug "$(m.name) finished waiting for inputs"

        failed_deps = Resources[]
        for (j, input) = enumerate(m.inputs)
            if inputs[j] == :failed
                push!(failed_deps, input)
            end
        end
        try
            isempty(failed_deps) || throw(FailedDepsException(failed_deps))
            outputs, t, _ = Base.@timed m.f(inputs)
            for (j, o) in enumerate(m.outputs)
                put!(ChannelDict[o], outputs[j] )
            end
            @info "$(m.name) finished ($(round(t,digits=3))s)"
        catch E
            @error "$(m.name) failed" exception=E
            for o in m.outputs
                put!(ChannelDict[o], :failed )
            end
            if m.throw
                rethrow(E)
            end
        end
        
    end

end


function get_do_list(G, make_list, targets)
    do_edges = get_edge_list(G, targets)
    do_list = Set(Make[])
    for e in do_edges
        idx = get_prop(G, e, :make_idx)
        push!(do_list, make_list[idx])
    end
    return do_list
end
function walk!(do_edges, v, G)
    nhbrs = inneighbors(G, v)
    union!(do_edges, [Edge( n => v) for n in nhbrs] )
    foreach(nhbrs) do n
        walk!(do_edges, n, G)
    end
end
function get_edge_list(G, targets)
    source_node = G[RAW_JSON, :name]
    do_edges = Set(Edge[])
    for tar in targets
        walk!(do_edges, G[tar, :name], G)
    end
    return do_edges
end

function build_DAG(make_list)
    vertex_names = union(instances(InternalResources), instances(BuildTargets))
    G = MetaDiGraph(SimpleDiGraph(length(vertex_names)))
    for (index, name) = enumerate(vertex_names)
        set_prop!(G, index, :name, name)
    end
    set_indexing_prop!(G, :name)
    verticies_dict = Dict(zip(vertex_names,1:length(vertex_names)))

    for (index, make_obj) in enumerate(make_list)
        for i in make_obj.inputs
            i_ind = verticies_dict[i]
            for o in make_obj.outputs
                o_ind = verticies_dict[o]
                add_edge!(G, i_ind => o_ind)
                set_prop!(G, i_ind, o_ind, :edge_name, make_obj.name)
                set_prop!(G, i_ind, o_ind, :make_idx, index)
            end
        end
    end
    return G
end