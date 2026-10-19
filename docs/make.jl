using Documenter, PolycubePuzzles

DocMeta.setdocmeta!(PolycubePuzzles, :DocTestSetup, :(using PolycubePuzzles); recursive = true)

makedocs(;
    modules = [PolycubePuzzles],
    sitename = "PolycubePuzzles.jl",
    authors = "Michael McVeagh",
    format = Documenter.HTML(; canonical = "https://mcvmcv.github.io/PolycubePuzzles.jl",
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

deploydocs(; repo = "github.com/mcvmcv/PolycubePuzzles.jl", devbranch = "main")
