# Assembly instructions: a building order for a solution, and a colouring of
# its pieces in which touching pieces differ. Plotting lives in the Makie
# extension; these are plain Julia so they can be tested and reused.

neighbors(c::NTuple{N,Int}) where {N} =
    (ntuple(i -> c[i] + (i == d) * s, N) for d in 1:N for s in (-1, 1))

"""
    assembly_order(sol::Solution; up = N)

An order in which to place the pieces of `sol` when building it by hand, as a
permutation of `1:length(sol)`. Axis `up` points up (default: the last axis, z
in 3D and y in 2D). The pieces are added bottom-up. At each step the order
prefers a piece that

1. rests entirely on the floor, on placed pieces, or on itself, and
2. can be lowered straight down without hitting a placed piece,

and among those it takes the lowest. If no piece rests entirely, it takes the
one with the most supported cells.
"""
function assembly_order(sol::Solution{N}; up::Int = N) where {N}
    pls = sol.placements
    isempty(pls) && return Int[]
    owner = Dict(c => k for (k, pl) in enumerate(pls) for c in pl.cells)
    floor = minimum(c[up] for c in keys(owner))
    top = maximum(c[up] for c in keys(owner))
    placed = falses(length(pls))
    below(c) = ntuple(i -> c[i] - (i == up), N)
    function supported(k, c)
        c[up] == floor && return true
        o = get(owner, below(c), 0)
        o != 0 && (o == k || placed[o])
    end
    function droppable(k)
        for c in pls[k].cells, h in c[up]+1:top
            o = get(owner, ntuple(i -> i == up ? h : c[i], N), 0)
            o != 0 && o != k && placed[o] && return false
        end
        true
    end
    order = Int[]
    for _ in eachindex(pls)
        best, bestscore = 0, nothing
        for k in eachindex(pls)
            placed[k] && continue
            cells = pls[k].cells
            nsup = count(c -> supported(k, c), cells)
            rests = nsup == length(cells)
            heights = [c[up] for c in cells]
            # lexicographic: rests & droppable, rests, support fraction, low, then index
            score = (!(rests && droppable(k)), !rests, -nsup / length(cells),
                     minimum(heights), sum(heights) / length(heights), k)
            if bestscore === nothing || score < bestscore
                best, bestscore = k, score
            end
        end
        placed[best] = true
        push!(order, best)
    end
    order
end

"""
    piece_coloring(sol::Solution) -> Vector{Int}

A colour index for each piece of `sol` such that face-adjacent pieces get
different colours, using few colours (DSatur greedy colouring).
"""
function piece_coloring(sol::Solution{N}) where {N}
    pls = sol.placements
    n = length(pls)
    owner = Dict(c => k for (k, pl) in enumerate(pls) for c in pl.cells)
    adj = [Set{Int}() for _ in 1:n]
    for (k, pl) in enumerate(pls), c in pl.cells, d in neighbors(c)
        o = get(owner, d, 0)
        o != 0 && o != k && push!(adj[k], o)
    end
    color = zeros(Int, n)
    for _ in 1:n
        # most distinct neighbour colours, then most neighbours
        k = argmax(k -> color[k] == 0 ? (length(Set(color[j] for j in adj[k] if color[j] != 0)), length(adj[k])) : (-1, -1), 1:n)
        used = Set(color[j] for j in adj[k])
        color[k] = findfirst(c -> !(c in used), 1:n+1)
    end
    color
end

"""
    plot_solution(sol::Solution; step = length(sol), order = assembly_order(sol), kw...)

Plot a 2D or 3D solution, showing the first `step` pieces of `order`. When
`step < length(sol)` the newest piece is highlighted and the rest are muted.
Returns a Makie `Figure`. Requires a Makie backend, e.g. `using CairoMakie`.
"""
function plot_solution end

"""
    plot_solution!(ax, sol::Solution; step, order, kw...)

Draw a solution into an existing Makie axis (`Axis` for 2D, `Axis3` or `LScene`
for 3D). See [`plot_solution`](@ref).
"""
function plot_solution! end

"""
    plot_steps(sol::Solution; order = assembly_order(sol), columns = 5, kw...)

A Makie `Figure` with one panel per assembly step, numbered, each showing the
pieces placed so far with the newest one highlighted.
"""
function plot_steps end

"""
    animate_assembly(sol::Solution, filename; order = assembly_order(sol), framerate = 1, kw...)

Record an animation (`.gif`, `.mp4`, ...) of the solution being assembled one
piece at a time, and return `filename`.
"""
function animate_assembly end
