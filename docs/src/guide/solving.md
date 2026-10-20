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

## Ignoring swapped pairs

Many solutions differ only in a small rearrangement. Two touching pieces
whose cells together can be filled by the same two pieces in another way can
trade places, and the rest of the solution doesn't change. In the 5×5×5 cube
of Y pentacubes, two Ys lying side by side with their nubs together make an H
with a thick bar, and the two nubs can swap. Nearly every solution has a few
such pairs, and each one doubles the count.

`swaps = true` counts solutions that differ only by such swaps (or chains of
them) once. With `symmetry`, one solution is kept for each family of
solutions related by swaps and symmetries:

```jldoctest
julia> count_solutions(S; symmetry = :all, swaps = true)
40
```

```julia
count_solutions(y5; symmetry = :all)                 # 1264
count_solutions(y5; symmetry = :all, swaps = true)   # 106
```

Only swaps between two pieces are found, not rearrangements of three or more.
Finding the families means enumerating solutions, so `swaps = true` is no
faster than finding every solution with the same `symmetry`; [`solve`](@ref)
returns the first solution of each family in search order.

## Threads

The search can be split over several tasks, using the `ntasks` keyword.
[`solve`](@ref) and [`count_solutions`](@ref) default to one task per Julia
thread, so starting Julia with `julia --threads=auto` uses every core. The
order of the results doesn't depend on the number of tasks.

## How it works

Each puzzle becomes an *exact cover* problem: choose placements of pieces so
that every target cell is covered exactly once. Instead of one constraint per
copy of a piece, each piece type has a counter, so identical copies are never
told apart. There are two search engines:

- **Bitboard**: the filled cells are a bitset and every placement a
  precomputed mask. The search always fills the first empty cell, working
  along the target's shortest direction first, so each step is just a couple
  of bitwise operations. This is fastest for most flat puzzles: all 2339
  pentomino solutions of the 10×6 rectangle take about 1.5 s.
- **Dancing links** (Knuth's Algorithm X): always fills the cell with the
  fewest ways left to fill it. Each step costs more, but the search can be far
  smaller. For the 5×5×5 cube of Y pentacubes it is hundreds of times faster
  than the bitboard search.

By default (`engine = :auto`) both are estimated with Knuth's random-probe
method, a few hundred random walks down each search tree, which takes a few
hundredths of a second, and the faster one is used. Pass `engine = :dlx` or
`engine = :bitboard` to choose.
