"""
    Polyominoes

Solve packing puzzles: fill a target region of the N-dimensional integer lattice
with a given multiset of pieces (polyominoes, polycubes, ...). Puzzles are
reduced to exact cover and solved with Knuth's dancing links (Algorithm X),
extended with per-piece-type count bounds so identical pieces are never
distinguished (no duplicate solutions from permuting copies).
"""
module Polyominoes

export Shape, @shape_str, parse_shape, box, normalize, ncells
export orientations
export Puzzle, Placement, Solution, placements
export solve, count_solutions, foreach_solution
export pentominoes, soma
export assembly_order, assembly_plan, insertion, isassemblable, Insertion, piece_coloring
export plot_solution, plot_solution!, plot_steps, animate_assembly

include("shapes.jl")
include("orientations.jl")
include("puzzle.jl")
include("dlx.jl")
include("symmetry.jl")
include("solve.jl")
include("library.jl")
include("assembly.jl")

end
