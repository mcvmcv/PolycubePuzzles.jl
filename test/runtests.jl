using Polyominoes
using Test

const P5 = pentominoes()
const Y = shape"""
XXXX
.X..
"""


# Independent orbit count: enumerate all solutions, then identify those related
# by a geometric symmetry of the target that maps the solution set to itself.
function naive_orbits(p::Puzzle{N}, mode) where {N}
    raw = solve(p; ntasks = 1)
    label(cells) = minimum(orientations(normalize(Shape(cells)); reflections = p.reflections))
    key(sol) = sort([(label(pl.cells), sort(pl.cells)) for pl in sol])
    keys = Set(key(s) for s in raw)
    t0 = normalize(p.target)
    gs = []
    for (perm, signs) in Polyominoes.symmetries(N; reflections = true)
        mode === :rotations && Polyominoes.parity(perm) * prod(signs) == -1 && continue
        img = Shape([Polyominoes.transform(c, perm, signs) for c in p.target.cells])
        normalize(img) == t0 || continue
        off = first(Polyominoes.bounds(p.target.cells)) .- first(Polyominoes.bounds(img.cells))
        g(c) = Polyominoes.transform(c, perm, signs) .+ off
        image(sol) = sort([(label(map(g, pl.cells)), sort(map(g, pl.cells))) for pl in sol])
        all(s -> image(s) in keys, raw) && push!(gs, image)
    end
    count(s -> all(image -> key(s) <= image(s), gs), raw)
end

@testset "Polyominoes" begin
    @testset "shapes" begin
        @test Y == Shape((1, 2), (2, 2), (3, 2), (4, 2), (2, 1))
        @test ncells(box(5, 5, 5)) == 125
        @test (2, 3) in box(2, 3)
        @test !((3, 1) in box(2, 3))
        @test Shape(Bool[1 0; 1 1]) == Shape((1, 1), (2, 1), (2, 2))
        @test normalize(Shape((5, 7), (6, 7))) == Shape((1, 1), (2, 1))
        @test ncells(setdiff(box(3, 3), Shape((2, 2)))) == 8

        L3 = shape"""
        XX
        X.

        X.
        ..
        """
        @test L3 isa Shape{3}
        @test L3 == Shape((1, 2, 1), (2, 2, 1), (1, 1, 1), (1, 2, 2))
        @test_throws ArgumentError parse_shape("X\n\nX\nX")
    end

    @testset "orientations" begin
        @test length(orientations(Y; reflections = true)) == 8
        @test length(orientations(Y; reflections = false)) == 4
        @test length(orientations(P5.X; reflections = true)) == 1
        @test length(orientations(P5.I; reflections = true)) == 2
        @test length(orientations(P5.F; reflections = true)) == 8
        @test sum(length(orientations(s; reflections = true)) for s in P5) == 63
        Y3 = Shape([(c..., 1) for c in Y])
        @test length(orientations(Y3; reflections = false)) == 24
        @test length(orientations(Y3; reflections = true)) == 24  # planar, so mirror is a rotation
        @test length(orientations(box(1, 1, 1); reflections = true)) == 1
    end

    @testset "counts and multiplicities" begin
        mono, dom = Shape((1, 1)), Shape((1, 1), (2, 1))
        # tilings of a 1x3 strip with interchangeable monominoes and dominoes
        @test count_solutions(Puzzle(box(3, 1), [mono => 0:3, dom => 0:3])) == 3
        @test count_solutions(Puzzle(box(3, 1), [mono => 1, dom => 1])) == 2
        @test count_solutions(Puzzle(box(3, 1), [mono => 3, dom => 0:1])) == 1
        @test count_solutions(Puzzle(box(3, 1), dom => 2)) == 0
        # domino tilings of a 2xn strip are Fibonacci numbers
        @test count_solutions(Puzzle(box(2, 10), dom => 10)) == 89
        # domino tilings of the 2x2x2 cube
        @test count_solutions(Puzzle(box(2, 2, 2), Shape((1, 1, 1), (2, 1, 1)) => 4)) == 9
        # spare pieces allowed
        @test count_solutions(Puzzle(box(2, 2), [dom => 0:5])) == 2
    end

    @testset "pentomino rectangles" begin
        pieces = [s => 1 for s in P5]
        # known solution counts up to symmetry, times the 4 symmetries of a rectangle
        @test count_solutions(Puzzle(box(20, 3), pieces)) == 2 * 4
        @test count_solutions(Puzzle(box(15, 4), pieces)) == 368 * 4
    end

    @testset "symmetry reduction" begin
        pieces = [s => 1 for s in P5]
        @test count_solutions(Puzzle(box(20, 3), pieces); symmetry = :all) == 2
        @test count_solutions(Puzzle(box(15, 4), pieces); symmetry = :all) == 368
        ring = setdiff(box(8, 8), Shape([(x, y) for x in 4:5 for y in 4:5]))
        @test count_solutions(Puzzle(ring, pieces); symmetry = :all) == 65
        S = Puzzle(box(3, 3, 3), [s => 1 for s in soma()])
        @test count_solutions(S) == 11520
        @test count_solutions(S; symmetry = :rotations) == 480
        @test count_solutions(S; symmetry = :all) == 240  # mirror swaps the A/B screws
        @test_throws ArgumentError count_solutions(S; symmetry = :bogus)
        @test_throws ArgumentError Puzzle(box(3, 3, 3), Shape((1, 1)) => 1)

        mono, dom = Shape((1, 1)), Shape((1, 1), (2, 1))
        L3, I3 = shape"X.\nXX", shape"XXX"
        V3 = Shape((1, 1, 1), (2, 1, 1), (1, 2, 1))
        A, B = soma().A, soma().B
        dom3 = Shape((1, 1, 1), (2, 1, 1))
        cases = [
            Puzzle(box(2, 2, 2), Shape((1, 1, 1), (2, 1, 1)) => 4),
            Puzzle(box(4, 4), [mono => 0:4, dom => 0:8]),
            Puzzle(box(3, 4), [L3 => 0:4, I3 => 1:2]),
            Puzzle(box(3, 3), [L3 => 2, I3 => 0:1, mono => 0:3]),
            Puzzle(shape"XXX\nX.X\nXXX", [L3 => 0:2, dom => 0:4, mono => 0:1]),
            Puzzle(box(2, 2, 3), [V3 => 2, A => 0:1, B => 0:1, dom3 => 0:6]; reflections = false),
            Puzzle(box(2, 3, 2), [A => 1, B => 1, V3 => 0:4]),
        ]
        for p in cases, mode in (:rotations, :all)
            @test count_solutions(p; symmetry = mode) == naive_orbits(p, mode)
        end
    end

    @testset "parallel search" begin
        S = Puzzle(box(3, 3, 3), [s => 1 for s in soma()])
        @test count_solutions(S; ntasks = 4) == 11520
        @test count_solutions(S; symmetry = :all, ntasks = 4) == 240
        p = Puzzle(box(15, 4), [s => 1 for s in P5])
        @test solve(p; ntasks = 4) == solve(p; ntasks = 1)
        @test length(solve(p; ntasks = 4, limit = 10)) == 10
        n = Threads.Atomic{Int}(0)
        @test foreach_solution(_ -> (Threads.atomic_add!(n, 1); true), S; ntasks = 4)
        @test n[] == 11520
        @test !foreach_solution(_ -> false, S; ntasks = 4)
    end

    @testset "assembly" begin
        Y3 = Shape([(c..., 1) for c in Y])
        sol = solve(Puzzle(box(5, 5, 5), Y3 => 25); limit = 1)[1]
        order = assembly_order(sol)
        @test sort(order) == 1:25
        # every piece rests on the floor, earlier pieces, or itself when placed
        placed = Set{NTuple{3,Int}}()
        for k in order
            cells = sol.placements[k].cells
            own = Set(cells)
            @test all(c -> c[3] == 1 || (c .- (0, 0, 1)) in placed || (c .- (0, 0, 1)) in own, cells)
            union!(placed, cells)
        end
        col = piece_coloring(sol)
        owner = Dict(c => k for (k, pl) in enumerate(sol) for c in pl.cells)
        @test all(owner) do (c, k)
            all(d -> (o = get(owner, d, k); o == k || col[o] != col[k]), Polyominoes.neighbors(c))
        end
        @test maximum(col) <= 8
        p2 = solve(Puzzle(box(10, 6), [s => 1 for s in P5]); limit = 1)[1]
        @test sort(assembly_order(p2)) == 1:12
        @test maximum(piece_coloring(p2)) <= 4
    end

    @testset "solutions are valid" begin
        p = Puzzle(box(20, 3), [s => 1 for s in P5])
        sols = solve(p)
        @test length(sols) == 8
        for s in sols
            cells = reduce(vcat, [pl.cells for pl in s])
            @test sort(cells) == box(20, 3).cells
            @test sort([pl.piece for pl in s]) == 1:12
        end
        @test length(solve(p; limit = 3)) == 3
        @test occursin("Solution{2} with 12 pieces", repr("text/plain", sols[1]))
    end
end
