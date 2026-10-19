# Assembly instructions: a building order for a solution, and a colouring of
# its pieces in which touching pieces differ. Plotting lives in the Makie
# extension; these are plain Julia so they can be tested and reused.

neighbors(c::NTuple{N,Int}) where {N} =
    (ntuple(i -> c[i] + (i == d) * s, N) for d in 1:N for s in (-1, 1))

"""
    sightlines(owner, k, isplaced, view) -> (nfaces, nvisible, occluders)

For piece `k` in a cell => piece map `owner`, look along `view` (pointing
towards the viewer) from the centre of each of its faces that faces the
viewer. Returns the number of such faces, how many are not hidden by a placed
piece (`isplaced(o)`), and the set of placed pieces hiding them.
"""
function sightlines(owner::Dict{NTuple{N,Int},Int}, k::Int, isplaced, view) where {N}
    v = Float64.(Tuple(view)) ./ sqrt(sum(abs2, view))
    lo, hi = bounds(collect(keys(owner)))
    reach = 2 * sum(hi .- lo .+ 1)
    occluders = Set{Int}()
    nface = nseen = 0
    for (c, o) in owner
        o == k || continue
        for d in 1:N, s in (-1, 1)
            s * v[d] > 0 || continue
            # skip faces in contact with the piece itself or a placed piece
            nb = get(owner, ntuple(i -> c[i] + (i == d) * s, N), 0)
            (nb == k || (nb != 0 && isplaced(nb))) && continue
            nface += 1
            # march from the face centre towards the viewer
            p = ntuple(i -> c[i] - 0.5 + (i == d) * 0.5 * s, N)
            hidden = false
            for t in 0.05:0.1:reach
                q = ntuple(i -> ceil(Int, p[i] + t * v[i]), N)
                any(i -> !(lo[i] <= q[i] <= hi[i]), 1:N) && break
                o = get(owner, q, 0)
                if o != 0 && o != k && isplaced(o)
                    hidden = true
                    push!(occluders, o)
                end
            end
            nseen += !hidden
        end
    end
    nface, nseen, occluders
end

"""
    assembly_order(sol::Solution; up = N, view = nothing, right = nothing)

An order in which to place the pieces of `sol` when building it by hand, as a
permutation of `1:length(sol)`. Axis `up` points up (default: the last axis, z
in 3D and y in 2D). At each step the order prefers a piece that

1. rests entirely on the floor, on placed pieces, or on itself, and
2. can be lowered straight down without hitting a placed piece.

Among those it takes the lowest piece. If `view`, a vector pointing from the
puzzle towards the viewer, is given, it instead prefers pieces that would be
mostly visible from the viewer (not hidden behind placed pieces), and among
those the one farthest from the viewer, so later pieces go in front;
`right`, the viewer's rightward direction, then favours pieces on the left.
If no piece rests entirely, it takes the one with the most supported cells.
"""
function assembly_order(sol::Solution{N}; up::Int = N, view = nothing, right = nothing) where {N}
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
    function visibility(k)
        view === nothing && return 1.0
        nface, nseen, _ = sightlines(owner, k, o -> placed[o], view)
        nface == 0 ? 1.0 : nseen / nface
    end
    along(v, cells) = v === nothing ? 0.0 : sum(c -> sum(c .* v), cells) / length(cells)
    # depth toward the viewer, with leftness as a lesser tie-breaker
    position(cells) = along(view, cells) + 0.35 * along(right, cells)
    order = Int[]
    for _ in eachindex(pls)
        best, bestscore = 0, nothing
        for k in eachindex(pls)
            placed[k] && continue
            cells = pls[k].cells
            nsup = count(c -> supported(k, c), cells)
            rests = nsup == length(cells)
            heights = [c[up] for c in cells]
            # lexicographic: rests & droppable, rests, support fraction, mostly visible,
            # position, low, then index
            score = (!(rests && droppable(k)), !rests, -nsup / length(cells),
                     rests && visibility(k) < 0.6, round(position(cells); digits = 6), minimum(heights),
                     sum(heights) / length(heights), k)
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
