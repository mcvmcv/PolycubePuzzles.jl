using Polyominoes
using Test

const P5 = pentominoes()
const Y = shape"""
XXXX
.X..
"""

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
