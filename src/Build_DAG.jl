@enum InternalResources RAW_TEX_JSON RAW_WEB_JSON FILT_TEX_JSON FILT_WEB_JSON TEX_AUX_PATH TEX_FILE_PATH PARSE_TEX_LOG

const Resources = Union{InternalResources, BuildTargets}


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
        inputs = [ fetch(ChannelDict[i]) for i in m.inputs ]
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


# task_list = start_make.(make_list)