"""
    Shape{N}

A finite set of cells in the N-dimensional integer lattice, stored as a sorted
vector of unique `NTuple{N,Int}` coordinates. Shapes are used both for pieces
and for target regions.

Construct with:
- `Shape(cells...)` or `Shape(cells::AbstractVector)` from coordinate tuples,
- `Shape(A::AbstractArray{Bool})` from a boolean array (cells where `true`),
- `shape"..."` / [`parse_shape`](@ref) from ASCII art,
- [`box`](@ref) for rectangular boxes.

Set operations `union`, `intersect` and `setdiff` work on shapes of equal
dimension, so a target with holes is e.g. `setdiff(box(5,5), Shape((3,3)))`.
"""
struct Shape{N}
    cells::Vector{NTuple{N,Int}}
    Shape{N}(cells) where {N} = new{N}(sort!(unique!(collect(NTuple{N,Int}, cells))))
end

Shape(cells::AbstractVector{<:NTuple{N,Integer}}) where {N} = Shape{N}(cells)
Shape(cells::NTuple{N,Integer}...) where {N} = Shape{N}(collect(cells))
Shape(A::AbstractArray{Bool,N}) where {N} = Shape{N}([Tuple(I) for I in findall(A)])

"""
    box(dims...)

The rectangular box `1:dims[1] × 1:dims[2] × ...`.
"""
box(dims::Integer...) = Shape{length(dims)}(vec([Tuple(I) for I in CartesianIndices(dims)]))

"""
    ncells(s::Shape)

The number of cells in `s`.
"""
ncells(s::Shape) = length(s.cells)
Base.length(s::Shape) = length(s.cells)
Base.iterate(s::Shape, st...) = iterate(s.cells, st...)
Base.eltype(::Type{Shape{N}}) where {N} = NTuple{N,Int}
Base.in(c::NTuple{N,Integer}, s::Shape{N}) where {N} = insorted(c, s.cells)
Base.:(==)(a::Shape, b::Shape) = a.cells == b.cells
Base.hash(s::Shape, h::UInt) = hash(s.cells, hash(:Shape, h))
Base.isless(a::Shape, b::Shape) = isless(a.cells, b.cells)

Base.union(a::Shape{N}, b::Shape{N}) where {N} = Shape{N}(vcat(a.cells, b.cells))
Base.intersect(a::Shape{N}, b::Shape{N}) where {N} = Shape{N}(intersect(a.cells, b.cells))
Base.setdiff(a::Shape{N}, b::Shape{N}) where {N} = Shape{N}(setdiff(a.cells, b.cells))

"""
    normalize(s::Shape)

Translate `s` so that its minimum coordinate along every axis is 1.
"""
function normalize(s::Shape{N}) where {N}
    isempty(s.cells) && return s
    lo = ntuple(i -> minimum(c[i] for c in s.cells), N)
    Shape{N}([c .- lo .+ 1 for c in s.cells])
end

function bounds(cells::AbstractVector{NTuple{N,Int}}) where {N}
    lo = ntuple(i -> minimum(c[i] for c in cells), N)
    hi = ntuple(i -> maximum(c[i] for c in cells), N)
    lo, hi
end

"""
    parse_shape(str)

Parse a shape from ASCII art. `.` and spaces are empty; any other character is
a cell. Columns give the x coordinate (left to right) and lines give y, with the
*bottom* line being y = 1. Blocks of lines separated by blank lines are layers of
a 3D shape, the first block being z = 1 (bottom layer first). All layers must
have the same number of lines.

```julia
Y = shape\"\"\"
XXXX
.X..
\"\"\"
```
"""
function parse_shape(str::AbstractString)
    lines = rstrip.(split(str, '\n'))
    blocks = Vector{Vector{String}}()
    current = String[]
    for line in lines
        if isempty(strip(line))
            isempty(current) || push!(blocks, current)
            current = String[]
        else
            push!(current, line)
        end
    end
    isempty(current) || push!(blocks, current)
    isempty(blocks) && throw(ArgumentError("empty shape"))
    h = length(blocks[1])
    all(b -> length(b) == h, blocks) ||
        throw(ArgumentError("all layers of a 3D shape must have the same number of lines"))
    cells2 = NTuple{2,Int}[]
    cells3 = NTuple{3,Int}[]
    for (z, block) in enumerate(blocks), (i, line) in enumerate(block)
        y = h - i + 1
        for (x, ch) in enumerate(line)
            ch in ('.', ' ') && continue
            push!(cells2, (x, y))
            push!(cells3, (x, y, z))
        end
    end
    length(blocks) == 1 ? Shape{2}(cells2) : Shape{3}(cells3)
end

"""
    shape"..."

String macro for [`parse_shape`](@ref); the shape is built at parse time.
"""
macro shape_str(str)
    parse_shape(str)
end

# ASCII rendering of 2D and 3D cell labellings, shared by Shape and Solution.
function render(io::IO, labels::Dict{NTuple{N,Int},Char}) where {N}
    cells = collect(keys(labels))
    lo, hi = bounds(cells)
    if N == 2
        for y in hi[2]:-1:lo[2]
            for x in lo[1]:hi[1]
                print(io, get(labels, (x, y), '.'))
            end
            y == lo[2] || println(io)
        end
    elseif N == 3
        for z in lo[3]:hi[3]
            z == lo[3] || print(io, "\n\n")
            for y in hi[2]:-1:lo[2]
                for x in lo[1]:hi[1]
                    print(io, get(labels, (x, y, z), '.'))
                end
                y == lo[2] || println(io)
            end
        end
    else
        join(io, (string(c, " => ", l) for (c, l) in sort!(collect(labels))), "\n")
    end
end

Base.show(io::IO, s::Shape{N}) where {N} = print(io, "Shape{", N, "}(", ncells(s), " cells)")

function Base.show(io::IO, ::MIME"text/plain", s::Shape{N}) where {N}
    print(io, "Shape{", N, "} with ", ncells(s), " cells")
    isempty(s.cells) && return
    println(io, ":")
    render(io, Dict(c => 'X' for c in s.cells))
end
