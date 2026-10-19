using Documenter, Polyominoes

DocMeta.setdocmeta!(Polyominoes, :DocTestSetup, :(using Polyominoes); recursive = true)

makedocs(;
    modules = [Polyominoes],
    sitename = "Polyominoes.jl",
    authors = "Michael McVeagh",
    format = Documenter.HTML(; canonical = "https://mcvmcv.github.io/Polyominoes.jl",
                             edit_link = "main", assets = String[]),
    pages = [
        "Home" => "index.md",
        "Guide" => [
            "Describing puzzles" => "guide/describing.md",
            "Solving" => "guide/solving.md",
            "Assembly and plots" => "guide/assembly.md",
        ],
        "API" => "api.md",
    ],
    checkdocs = :exports,
)

deploydocs(; repo = "github.com/mcvmcv/Polyominoes.jl", devbranch = "main")
