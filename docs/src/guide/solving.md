# Solving

```@meta
DocTestSetup = quote
    using PolycubePuzzles
    S = Puzzle(box(3, 3, 3), [s => 1 for s in soma()])
end
```

Three functions search for solutions:

- [`solve`](@ref) returns them as a vector, up to an optional `limit`.
- [`count_solutions`](@ref) counts them without storing them.
- [`foreach_solution`](@ref) passes each one to a function as it is found;
  return `false` from the function to stop.

A [`Solution`](@ref) is a list of [`Placement`](@ref)s. It prints as letters,
one per piece, and 3D solutions print layer by layer.

## Counting up to symmetry

A solution turned around is usually counted as a different solution. The
`symmetry` keyword counts each family of related solutions once:

- `:none` (the default) counts every solution.
- `:rotations` treats solutions related by a rotation of the target as the same.
- `:all` also treats mirror images as the same, when a mirror image of a
  solution is itself a solution.

For the Soma cube, with its 7 pieces in a 3×3×3 cube:

```jldoctest
julia> count_solutions(S)
11520

julia> count_solutions(S; symmetry = :rotations)
480

julia> count_solutions(S; symmetry = :all)
240
```

The Soma pieces include a left-handed and a right-handed screw. Mirroring a
solution swaps them, so the mirror image is still a solution and `:all`
identifies the two. If a puzzle has pieces whose mirror images aren't
available, mirrored solutions can't be built and `:all` is the same as
`:rotations`.

The reduction is exact, and it also speeds the search up: it pins down one
piece (or the piece covering a central cell) to one representative position
per symmetry class before searching.

## Threads

The search can be split over several tasks, using the `ntasks` keyword.
[`solve`](@ref) and [`count_solutions`](@ref) default to one task per Julia
thread, so starting Julia with `julia --threads=auto` uses every core. The
order of the results doesn't depend on the number of tasks.

## How it works

Each puzzle becomes an *exact cover* problem: choose placements of pieces so
that every target cell is covered exactly once. It is solved with Knuth's
dancing links (Algorithm X). Instead of one constraint per copy of a piece,
each piece type has a counter, so identical copies are never told apart.
