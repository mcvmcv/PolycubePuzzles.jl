# API

```@docs
PolycubePuzzles
```

## Shapes

```@docs
Shape
@shape_str
parse_shape
box
normalize
ncells
orientations
```

## Puzzles and solutions

```@docs
Puzzle
Placement
Solution
placements
solve
count_solutions
foreach_solution
```

## Piece libraries

```@docs
pentominoes
soma
```

## Assembly

```@docs
assembly_order
assembly_plan
insertion
Insertion
isassemblable
piece_coloring
```

## Plotting

These need a Makie backend, e.g. `using CairoMakie`.

```@docs
plot_solution
plot_solution!
plot_steps
animate_assembly
```
