using NodeJS

# from https://github.com/fredo-dedup/VegaLite.jl/blob/master/deps/build.jl
run(Cmd(`$(npm_cmd()) install katex --production --no-bin-links --no-package-lock --no-optional`, dir=@__DIR__))


# to do: add checks for existence of `pdf2svg`, `pdflatex`, `latexmk`, `convert`