# Polyominoes.jl

Solve packing puzzles in any dimension: fill a target region with a given
multiset of pieces (polyominoes, polycubes, ...), enumerate all solutions,
count them up to symmetry, and plot step-by-step assembly instructions.

```julia
using Polyominoes

Y = shape"""
XXXX
.X..
"""
Y3 = Shape([(c..., 1) for c in Y])          # the same piece in 3D
p = Puzzle(box(5, 5, 5), Y3 => 25)

solve(p; limit = 1)                          # one solution, printed layer by layer
count_solutions(p)                           # 60672
count_solutions(p; symmetry = :all)          # 1264 up to rotation and reflection
```

## Describing puzzles

**Shapes** are finite sets of integer cells, `Shape{N}`, 1-based:

- `Shape((1,1), (2,1), (2,2))` from coordinate tuples (any dimension),
- `Shape(A)` from a `Bool` array,
- `box(5, 5, 5)` for boxes,
- `shape"..."` from ASCII art. `.` and spaces are empty, any other character is
  a cell; columns are x, lines are y with the **bottom line y = 1**; blocks
  separated by blank lines are the z-layers of a 3D shape, **bottom layer first**,
- `union`, `intersect`, `setdiff` for anything else, e.g. a board with a hole:
  `setdiff(box(8, 8), Shape([(x, y) for x in 4:5 for y in 4:5]))`.

**Puzzles** pair a target with pieces and counts:

```julia
Puzzle(target, [pieceA => 1, pieceB => 3, pieceC => 0:2]; reflections = false)
```

A count is exact (`3`) or a range (`0:2`, for spare pieces). Copies of a piece
are indistinguishable, so permuting them never yields a "new" solution.
`reflections` says whether pieces may be mirrored; it defaults to `true` in 2D
(a tile can be turned over) and `false` otherwise.

The library has `pentominoes()` and `soma()`.

## Solving

- `solve(p; limit, symmetry, ntasks)` returns a `Vector{Solution}`,
- `count_solutions(p; symmetry, ntasks)` counts without storing,
- `foreach_solution(f, p; symmetry, ntasks)` streams solutions to `f`; return
  `false` to stop.

`symmetry = :all` counts solutions related by a symmetry of the target once
(reflections included when they map solutions to solutions, e.g. the Soma
cube's mirror-twin screws swap places); `:rotations` identifies rotations only;
`:none` (the default) counts every solution. The reduction is exact and also
prunes the search.

`ntasks` splits the search tree over concurrent tasks; start Julia with
`julia --threads=auto` to use all cores. `solve` and `count_solutions` default
to `Threads.nthreads()`.

The solver is Knuth's dancing links (Algorithm X), with a counter per piece type
in place of one column per copy.

## Assembly instructions and plots

`assembly_order(sol)` orders the pieces bottom-up so each one rests on the floor
or on pieces already placed, preferring pieces that can be lowered straight in.
`piece_coloring(sol)` colours pieces so touching pieces differ.

Plotting is a package extension, loaded with any Makie backend:

```julia
using CairoMakie                          # or GLMakie for interactive 3D
sol = solve(p; limit = 1)[1]
plot_solution(sol)                        # the finished puzzle
plot_steps(sol)                           # one numbered panel per step
animate_assembly(sol, "assembly.gif")     # one frame per step
```

Each step shows the piece just placed in colour with a heavy outline, the
earlier pieces muted, and a frame of the final shape for reference. Keywords:
`azimuth`, `elevation` (3D view), `order`, `colors`, `muted`, `frame`.
