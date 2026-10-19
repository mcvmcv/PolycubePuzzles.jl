# Describing puzzles

```@meta
DocTestSetup = :(using PolycubePuzzles)
```

A puzzle is a target region and a collection of pieces. Both are
[`Shape`](@ref)s: finite sets of cells in the integer lattice, in any
dimension. Coordinates are 1-based tuples, like Julia array indices.

## Shapes

From coordinates, in any dimension:

```jldoctest describing
julia> Shape((1, 1), (2, 1), (2, 2))
Shape{2} with 3 cells:
.X
XX
```

From ASCII art with the `shape"..."` string macro. A `.` or a space is empty
and any other character is a cell. Columns give x, left to right. Lines give
y, and the **bottom line is y = 1**, so the picture looks the way the shape
does when plotted:

```jldoctest describing
julia> Y = shape"""
       XXXX
       .X..
       """
Shape{2} with 5 cells:
XXXX
.X..

julia> Y.cells
5-element Vector{Tuple{Int64, Int64}}:
 (1, 2)
 (2, 1)
 (2, 2)
 (3, 2)
 (4, 2)
```

A 3D shape is drawn as layers separated by blank lines, **bottom layer
first**:

```julia
corner = shape"""
XX
X.

X.
..
"""
```

which is the same as

```jldoctest describing
julia> corner = parse_shape("XX\nX.\n\nX.\n..");

julia> ncells(corner), corner.cells
(4, [(1, 1, 1), (1, 2, 1), (1, 2, 2), (2, 2, 1)])
```

For anything else, use [`box`](@ref) for boxes, `Shape(A)` for a `Bool` array,
and the set operations `union`, `intersect` and `setdiff`. For example, an 8×8
board with the middle 2×2 removed:

```jldoctest describing
julia> board = setdiff(box(8, 8), Shape([(x, y) for x in 4:5 for y in 4:5]));

julia> ncells(board)
60
```

A piece's position doesn't matter: the solver tries every orientation and
every translation. [`orientations`](@ref) lists the orientations it uses.

## Pieces and counts

A [`Puzzle`](@ref) pairs a target with pieces and how many of each to use:

```julia
Puzzle(target, piece => 25)
Puzzle(target, [pieceA => 1, pieceB => 2, pieceC => 0:3])
```

A count is either exact (`2`) or a range (`0:3`), for puzzles with spare
pieces. Copies of a piece are interchangeable, so swapping two of them never
counts as a new solution.

The library has the twelve [`pentominoes`](@ref) and the seven [`soma`](@ref)
cube pieces.

## Reflections

By default pieces are only rotated, never mirrored, which is right for solid
pieces. If flat pieces may be turned over, as in most pentomino puzzles, ask
for reflections:

```jldoctest describing
julia> length(orientations(Y)), length(orientations(Y; reflections = true))
(4, 8)

julia> count_solutions(Puzzle(box(10, 5), Y => 10))
1

julia> count_solutions(Puzzle(box(10, 5), Y => 10; reflections = true))
10
```

A flat piece used in 3D, like the Y pentacube, has its mirror image among its
rotations anyway.

## Checking a solution by hand

Give each piece as the cells it occupies, and [`Solution`](@ref) checks the
result and says what is wrong if it isn't a solution:

```jldoctest describing
julia> p = Puzzle(box(2, 2), Shape((1, 1), (2, 1)) => 2);

julia> Solution(p, [[(1, 1), (2, 1)], [(1, 2), (2, 2)]]);

julia> Solution(p, [[(1, 1), (2, 1)], [(1, 1), (1, 2)]])
ERROR: ArgumentError: piece 2 overlaps another piece at (1, 1)
[...]
```
