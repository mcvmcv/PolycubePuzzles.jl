# Regenerate the figures used by README.md and the documentation. Run from an
# environment with Polyominoes and CairoMakie, e.g.
#
#     julia --project=examples -e 'using Pkg; Pkg.develop(path="."); Pkg.add("CairoMakie")'
#     julia --project=examples --threads=auto examples/figures.jl

using Polyominoes, CairoMakie

outdir = joinpath(@__DIR__, "..", "docs", "src", "assets")
mkpath(outdir)
fig(name) = joinpath(outdir, name)

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
save(fig("cube3_steps.png"), plot_steps(sol; columns = 3, panelsize = 300))
save(fig("cube3.png"), plot_solution(sol; size = (400, 400)))
animate_assembly(sol, fig("cube3.gif"); size = (400, 400))

# Another solution of the same puzzle, in which one piece must slide in sideways
slidey = first(s for s in solve(p; symmetry = :rotations)
               if any(ins -> ins.kind === :slide, assembly_plan(s)))
save(fig("cube3_slide_steps.png"), plot_steps(slidey; columns = 3, panelsize = 300))
save(fig("cube3_slide_steps_wood.png"), plot_steps(slidey; columns = 3, panelsize = 300, style = :wood))

# The 5x5x5 cube from 25 Y pentacubes
Y = shape"""
XXXX
.X..
"""
y5 = Puzzle(box(5, 5, 5), Shape([(c..., 1) for c in Y]) => 25)
sol5 = solve(y5; limit = 1)[1]
save(fig("y5_steps.png"), plot_steps(sol5; panelsize = 300))
save(fig("y5_wood.png"), plot_solution(sol5; style = :wood, size = (500, 500)))
animate_assembly(sol5, fig("y5.gif"); size = (500, 500))

# Pentominoes in a 10x6 rectangle
pent = solve(Puzzle(box(10, 6), [s => 1 for s in pentominoes()]; reflections = true); limit = 1)[1]
save(fig("pentominoes.png"), plot_solution(pent; size = (500, 300)))
save(fig("pentominoes_wood.png"), plot_solution(pent; style = :wood, size = (500, 300)))
save(fig("pentominoes_steps.png"), plot_steps(pent; columns = 4, panelsize = 250))
