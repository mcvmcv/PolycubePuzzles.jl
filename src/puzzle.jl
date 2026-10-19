"""
    Puzzle(target::Shape{N}, pieces; reflections = (N == 2))

A packing puzzle: cover every cell of `target` exactly once using the given
pieces. `pieces` is a `piece => count` pair or a vector of them, where `count`
is an `Int` (use exactly that many) or a `UnitRange` (use between `first` and
`last` copies). Copies of one piece type are indistinguishable, so solutions
that only permute them are counted once.

`reflections` controls whether pieces may be mirrored. The default allows it in
2D (a flat piece can be turned over) and forbids it otherwise (a physical 3D
piece can't be mirrored). Note that a planar piece in 3D has its mirror image
among its rotations anyway.
"""
struct Puzzle{N}
    target::Shape{N}
    pieces::Vector{Shape{N}}
    counts::Vector{UnitRange{Int}}
    reflections::Bool
end

countrange(n::Integer) = Int(n):Int(n)
countrange(r::AbstractUnitRange{<:Integer}) = Int(first(r)):Int(last(r))

function Puzzle(target::Shape{N}, pieces::AbstractVector{<:Pair}; reflections::Bool = (N == 2)) where {N}
    shapes = Shape{N}[first(p) for p in pieces]
    counts = UnitRange{Int}[countrange(last(p)) for p in pieces]
    all(r -> first(r) >= 0 && !isempty(r), counts) ||
        throw(ArgumentError("piece counts must be non-negative and non-empty"))
    Puzzle{N}(target, shapes, counts, reflections)
end

Puzzle(target::Shape, piece::Pair; kw...) = Puzzle(target, [piece]; kw...)

"""
    Placement{N}

One piece placed in the target: `piece` is its index into `puzzle.pieces` and
`cells` the target cells it occupies.
"""
struct Placement{N}
    piece::Int
    cells::Vector{NTuple{N,Int}}
end

"""
    placements(p::Puzzle)

Every way of placing a single piece (any type, any allowed orientation) inside
the target.
"""
placements(p::Puzzle) = first(placement_rows(p))

# Placements together with the target-cell indices each one covers.
function placement_rows(p::Puzzle{N}) where {N}
    index = Dict(c => i for (i, c) in enumerate(p.target.cells))
    out = Placement{N}[]
    rows = Vector{Int}[]
    for (t, piece) in enumerate(p.pieces)
        last(p.counts[t]) == 0 && continue
        for o in orientations(piece; reflections = p.reflections)
            anchor = o.cells[1]
            for c0 in p.target.cells
                offset = c0 .- anchor
                ids = Int[]
                for c in o.cells
                    i = get(index, c .+ offset, 0)
                    i == 0 && break
                    push!(ids, i)
                end
                length(ids) == length(o.cells) || continue
                push!(out, Placement{N}(t, [c .+ offset for c in o.cells]))
                push!(rows, ids)
            end
        end
    end
    out, rows
end

"""
    Solution{N}

A solution of a puzzle: a list of [`Placement`](@ref)s that exactly cover the
target. Displays as ASCII art (one letter per placed piece) in 2D and 3D.
"""
struct Solution{N}
    placements::Vector{Placement{N}}
end

Base.length(s::Solution) = length(s.placements)
Base.iterate(s::Solution, st...) = iterate(s.placements, st...)

const LABELS = ['A':'Z'; 'a':'z'; '0':'9']

function Base.show(io::IO, ::MIME"text/plain", s::Solution{N}) where {N}
    println(io, "Solution{", N, "} with ", length(s), " pieces:")
    labels = Dict{NTuple{N,Int},Char}()
    for (k, pl) in enumerate(s.placements), c in pl.cells
        labels[c] = k <= length(LABELS) ? LABELS[k] : '#'
    end
    render(io, labels)
end
