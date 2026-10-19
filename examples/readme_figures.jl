# Regenerate the figures in README.md. Run from an environment with
# Polyominoes and CairoMakie, e.g.
#
#     julia --project=examples -e 'using Pkg; Pkg.develop(path="."); Pkg.add("CairoMakie")'
#     julia --project=examples --threads=auto examples/readme_figures.jl

using Polyominoes, CairoMakie

outdir = joinpath(@__DIR__, "..", "docs", "images")
mkpath(outdir)

# A 3x3x3 cube from six pieces, given as they sit in a known solution
pieces = [
    [(1, 3, 1), (2, 3, 1), (3, 3, 1), (3, 2, 1), (1, 3, 2)],
    [(1, 2, 1), (2, 2, 1), (2, 1, 1), (1, 2, 2)],
    [(1, 1, 1), (3, 1, 1), (1, 1, 2), (2, 1, 2), (3, 1, 2)],
    [(2, 2, 2), (3, 2, 2), (3, 3, 2), (2, 2, 3)],
    [(2, 3, 2), (2, 3, 3), (3, 3, 3), (3, 2, 3), (3, 1, 3)],
    [(2, 1, 3), (1, 1, 3), (1, 2, 3), (1, 3, 3)],
]
p = Puzzle(box(3, 3, 3), [Shape(c) => 1 for c in pieces])
sol = Solution(p, pieces)
save(joinpath(outdir, "cube3_steps.png"), plot_steps(sol; columns = 3, panelsize = 300))
save(joinpath(outdir, "cube3.png"), plot_solution(sol; size = (400, 400)))
animate_assembly(sol, joinpath(outdir, "cube3.gif"); size = (400, 400))

# The 5x5x5 cube from 25 Y pentacubes
Y = shape"""
XXXX
.X..
"""
y5 = Puzzle(box(5, 5, 5), Shape([(c..., 1) for c in Y]) => 25)
sol5 = solve(y5; limit = 1)[1]
save(joinpath(outdir, "y5_steps.png"), plot_steps(sol5; panelsize = 300))
animate_assembly(sol5, joinpath(outdir, "y5.gif"); size = (500, 500))

# Pentominoes in a 10x6 rectangle
pent = solve(Puzzle(box(10, 6), [s => 1 for s in pentominoes()]); limit = 1)[1]
save(joinpath(outdir, "pentominoes.png"), plot_solution(pent; size = (500, 300)))
