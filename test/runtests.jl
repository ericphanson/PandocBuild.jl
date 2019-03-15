using PandocBuild, Logging

io = open("timing.log", "w+")
logger = SimpleLogger(io)
with_logger(logger) do
    @info "First run of math:"
    build(@__DIR__; filename="math", targets=[WEB])
    @info "Second run of math:"
    build(@__DIR__; filename="math", targets=[WEB])
    @info "Third run of math:"
    build(@__DIR__; filename="math", targets=[WEB])
    @info "First run of math2:"
    build(@__DIR__; filename="math2", targets=[WEB])
    @info "Second run of math2:"
    build(@__DIR__; filename="math2", targets=[WEB])
end

close(io)
