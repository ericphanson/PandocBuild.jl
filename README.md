# PandocBuild.jl

System of filters and scripts for a fast and robust way to generate LaTeX and HTML based exports from markdown.

Requires `pdflatex`, `latexmk`, `rubber-info`, and `pandoc`. `latexmk` must be at least version 4.4.2 (we use the `cd` flag), and `pandoc` should be at least version `2`.

Needs `ericphanson/PandocFilters.jl`, so to install:
```
] add https://github.com/ericphanson/PandocFilters.jl
] add https://github.com/ericphanson/PandocBuild.jl
```
