# Solver benchmarks, single-threaded. Run with
#     julia --project=. benchmark/bench.jl
using PolycubePuzzles

Y = shape"""
XXXX
.X..
"""
P5 = [s => 1 for s in pentominoes()]
cases = [
    "pentominoes 10x6, all solutions" => (Puzzle(box(10, 6), P5; reflections = true), :none, 9356),
    "pentominoes 10x6, up to symmetry" => (Puzzle(box(10, 6), P5; reflections = true), :all, 2339),
    "pentominoes 12x5, up to symmetry" => (Puzzle(box(12, 5), P5; reflections = true), :all, 1010),
    "Y pentacubes 5x5x5, up to symmetry" => (Puzzle(box(5, 5, 5), Shape([(c..., 1) for c in Y]) => 25), :all, 1264),
    "Soma cube, all solutions" => (Puzzle(box(3, 3, 3), [s => 1 for s in soma()]), :none, 11520),
]
count_solutions(Puzzle(box(20, 3), P5; reflections = true); ntasks = 1)   # compile
for (name, (p, sym, expected)) in cases
    t = @elapsed n = count_solutions(p; symmetry = sym, ntasks = 1)
    n == expected || error("$name: got $n, expected $expected")
    println(rpad(name, 40), lpad(string(round(t, digits = 2)), 8), " s")
end
