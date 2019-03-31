using GraphPlot, LightGraphs, MetaGraphs, Colors
using Compose: cm, SVG

using PandocBuild: get_edge_list

function plot_dag!(G; targets = [])
    highlight_color = colorant"orange"
    edge_color = colorant"lightgray"
    for e in edges(G)
        set_prop!(G, e, :color, edge_color)
    end
    if !isempty(targets)
        highlight_edges = get_edge_list(G, targets)
        for e in highlight_edges
            set_prop!(G, e, :color, highlight_color)
        end
    end


    vertex_names = get_prop.(Ref(G), 1:nv(G), Ref(:name))
    edge_names = []
    for e in edges(G)
        push!(edge_names, get_prop(G, e, :edge_name))
    end

    edgestrokec = []
    for e in edges(G)
        push!(edgestrokec, get_prop(G, e, :color))
    end
    layout=(args...)->spring_layout(args...; C=10)

    gplot(G, layout=layout, nodelabel=vertex_names, edgelabel = edge_names, edgestrokec = edgestrokec) |> SVG("G.svg", 16cm, 16cm)
end