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
    Insertion{N}

How a piece gets into place during assembly. `kind` is `:drop` (lowered
straight down), `:slide` (pushed straight in along one axis), `:path` (a
sequence of axis-aligned slides) or `:blocked` (no translation gets it in).
`moves` are the slides as displacement vectors, in order, taking the piece
from a position clear of the puzzle to its place.
"""
struct Insertion{N}
    kind::Symbol
    moves::Vector{NTuple{N,Int}}
end

Base.:(==)(a::Insertion, b::Insertion) = a.kind == b.kind && a.moves == b.moves

function Base.show(io::IO, ins::Insertion)
    print(io, "Insertion(:", ins.kind)
    isempty(ins.moves) || print(io, ", ", join(ins.moves, " then "))
    print(io, ")")
end

unit(d, s, N) = ntuple(i -> (i == d) * s, N)

# How can `cells` be moved from its place to clear of the box lo:hi without
# meeting a cell in `blocked`? Never passes below the floor (lo[up]).
function find_insertion(cells::Vector{NTuple{N,Int}}, blocked::Set{NTuple{N,Int}},
                        lo::NTuple{N,Int}, hi::NTuple{N,Int}, up::Int) where {N}
    cmin, cmax = bounds(cells)
    free(off) = !any(c -> (c .+ off) in blocked, cells)
    # entirely outside the box along some axis, but not under the floor
    outside(off) = any(i -> cmin[i] + off[i] > hi[i] || (i != up && cmax[i] + off[i] < lo[i]), 1:N)
    # straight out: upwards first (i.e. dropped in), then the other directions
    for (d, s) in [(up, 1); [(d, s) for d in 1:N for s in (-1, 1) if d != up]]
        t = 0
        while true
            t += 1
            off = unit(d, s, N) .* t
            free(off) || break
            outside(off) && return Insertion{N}(d == up ? :drop : :slide, [unit(d, -s, N) .* t])
        end
    end
    # breadth-first search over translations, within reach of the box
    rlo = ntuple(i -> i == up ? lo[i] - cmin[i] : lo[i] - cmax[i] - 1, N)
    rhi = ntuple(i -> hi[i] - cmin[i] + 1, N)
    origin = ntuple(_ -> 0, N)
    prev = Dict(origin => origin)
    queue = [origin]
    goal = nothing
    head = 1
    while head <= length(queue)
        off = queue[head]
        head += 1
        if outside(off)
            goal = off
            break
        end
        for d in 1:N, s in (-1, 1)
            nxt = off .+ unit(d, s, N)
            all(i -> rlo[i] <= nxt[i] <= rhi[i], 1:N) || continue
            haskey(prev, nxt) && continue
            free(nxt) || continue
            prev[nxt] = off
            push!(queue, nxt)
        end
    end
    goal === nothing && return Insertion{N}(:blocked, NTuple{N,Int}[])
    # walk from the goal back to the origin: that is the way in
    moves = NTuple{N,Int}[]
    off = goal
    while off != origin
        step = prev[off] .- off
        if !isempty(moves) && sign.(moves[end]) == step
            moves[end] = moves[end] .+ step
        else
            push!(moves, step)
        end
        off = prev[off]
    end
    Insertion{N}(:path, moves)
end

"""
    insertion(sol::Solution, k, placed; up = N) -> Insertion

How piece `k` of `sol` can be moved into place when the pieces `placed` (a
collection of piece indices) are already there. See [`Insertion`](@ref).
"""
function insertion(sol::Solution{N}, k::Integer, placed; up::Int = N) where {N}
    lo, hi = bounds(reduce(vcat, [pl.cells for pl in sol]))
    blocked = Set(c for j in placed if j != k for c in sol.placements[j].cells)
    find_insertion(sol.placements[k].cells, blocked, lo, hi, up)
end

"""
    assembly_plan(sol::Solution; order = assembly_order(sol), up = N) -> Vector{Insertion}

For each step of `order`, how that piece is moved into place. A step whose
`kind` is `:blocked` cannot be done by sliding the piece in.
"""
assembly_plan(sol::Solution{N}; order = assembly_order(sol), up::Int = N) where {N} =
    [insertion(sol, order[i], order[1:i-1]; up) for i in eachindex(order)]

# Can every piece not in `fixed` be added, one at a time by translation, to
# the pieces in `fixed`? Equivalently, can they all be removed one at a time
# from the finished solution. Removing a piece never blocks another, so greedy
# removal decides this, and its reverse is a valid order for adding them.
function completion_order(sol::Solution{N}, fixed, up::Int) where {N}
    lo, hi = bounds(reduce(vcat, [pl.cells for pl in sol]))
    present = Set(eachindex(sol.placements))
    todo = setdiff(present, fixed)
    removed = Int[]
    progress = true
    while !isempty(todo) && progress
        progress = false
        for k in sort!(collect(todo))
            blocked = Set(c for j in present if j != k for c in sol.placements[j].cells)
            if find_insertion(sol.placements[k].cells, blocked, lo, hi, up).kind != :blocked
                delete!(present, k)
                delete!(todo, k)
                push!(removed, k)
                progress = true
            end
        end
    end
    isempty(todo) ? reverse!(removed) : nothing
end

"""
    isassemblable(sol::Solution; up = N)

Whether `sol` can be built one piece at a time, each piece slid into place
(along any route of straight moves, never through the floor) without moving
the pieces already placed.
"""
isassemblable(sol::Solution{N}; up::Int = N) where {N} = completion_order(sol, Int[], up) !== nothing

# How much a piece's lowest level counts against its back/left position when
# ordering for a viewer, in cell widths per level. Tuned on 5x5x5 Y-pentacube
# solutions: 0.5-0.75 keeps lower back layers ahead of towers with the fewest
# hidden steps; at 1 or more, front floor pieces go first and hide later ones.
const LEVEL_WEIGHT = 0.6

const INSERTION_RANK = Dict(:drop => 0, :slide => 1, :path => 2, :blocked => 3)

"""
    assembly_order(sol::Solution; up = N, view = nothing, right = nothing)

An order in which to place the pieces of `sol` when building it by hand, as a
permutation of `1:length(sol)`. Axis `up` points up (default: the last axis, z
in 3D and y in 2D).

Every piece can be slid into place when its turn comes, and the remaining
pieces can still be added afterwards, whenever the solution can be built that
way at all (see [`isassemblable`](@ref) and [`assembly_plan`](@ref)). Within
that, at each step the order prefers a piece that rests entirely on the floor,
on placed pieces, or on itself, then one that can be dropped straight in over
one that must slide in from the side, and then the lowest piece.

If `view`, a vector pointing from the puzzle towards the viewer, is given, it
instead prefers pieces that would be mostly visible from the viewer (not
hidden behind placed pieces), and among those the one farthest back, so later
pieces go in front, while still filling lower levels before higher ones;
`right`, the viewer's rightward direction, then favours pieces on the left.
"""
function assembly_order(sol::Solution{N}; up::Int = N, view = nothing, right = nothing) where {N}
    pls = sol.placements
    isempty(pls) && return Int[]
    owner = Dict(c => k for (k, pl) in enumerate(pls) for c in pl.cells)
    floor = minimum(c[up] for c in keys(owner))
    placed = falses(length(pls))
    below(c) = ntuple(i -> c[i] - (i == up), N)
    function supported(k, c)
        c[up] == floor && return true
        o = get(owner, below(c), 0)
        o != 0 && (o == k || placed[o])
    end
    function visibility(k)
        view === nothing && return 1.0
        nface, nseen, _ = sightlines(owner, k, o -> placed[o], view)
        nface == 0 ? 1.0 : nseen / nface
    end
    along(v, cells) = v === nothing ? 0.0 : sum(c -> sum(c .* v), cells) / length(cells)
    # depth toward the viewer, with leftness as a lesser tie-breaker
    position(cells) = along(view, cells) + 0.35 * along(right, cells)
    buildable = isassemblable(sol; up)
    order = Int[]
    for _ in eachindex(pls)
        candidates = Tuple[]
        for k in eachindex(pls)
            placed[k] && continue
            cells = pls[k].cells
            nsup = count(c -> supported(k, c), cells)
            rests = nsup == length(cells)
            rank = INSERTION_RANK[insertion(sol, k, findall(placed); up).kind]
            heights = [c[up] for c in cells]
            # lexicographic: insertable, rests, drop before slide before path, support
            # fraction, mostly visible, back/left position blended with lowest level,
            # lowest level, mean height, index
            push!(candidates, (rank == 3, !rests, rank, -nsup / length(cells),
                               rests && visibility(k) < 0.6,
                               round(position(cells) + LEVEL_WEIGHT * minimum(heights); digits = 6),
                               minimum(heights), sum(heights) / length(heights), k))
        end
        sort!(candidates)
        # take the best piece after which the rest can still be added
        best = last(first(candidates))
        if buildable
            for cand in candidates
                k = last(cand)
                if completion_order(sol, [findall(placed); k], up) !== nothing
                    best = k
                    break
                end
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
    plot_solution(sol::Solution; step = length(sol), kw...)

Plot a 2D or 3D solution as a Makie `Figure`, showing the first `step` pieces
of the assembly order. Requires a Makie backend, e.g. `using CairoMakie`.

Keywords:
- `step`: how many pieces to show. When `step < length(sol)` the newest piece
  is highlighted with a heavy outline and the earlier ones are muted.
- `order`: the assembly order; by default [`assembly_order`](@ref) for the
  plot's viewpoint (in 3D, from the back and left).
- `style`: `:flat` (default; plain colours) or `:wood` (wood tones with grain
  running along each piece).
- `colors`: the colours (or wood tones) to use; pieces are assigned them by
  [`piece_coloring`](@ref), so touching pieces differ.
- `azimuth`, `elevation`: the 3D viewing angles.
- `muted`: mute the earlier pieces when highlighting (default `true`).
- `ghost`: draw placed pieces that hide the newest one as faint ghosts
  (default `true`, 3D only).
- `arrows`: draw an arrow showing how the newest piece slides in, when it
  isn't simply dropped (default `true`).
- `frame`: draw the outline of the bounding box (default `true`).
- `size`: the figure size in pixels.
"""
function plot_solution end

"""
    plot_solution!(ax, sol::Solution; step, order, kw...)

Draw a solution into an existing Makie axis (`Axis` for 2D, `Axis3` or `LScene`
for 3D). See [`plot_solution`](@ref).
"""
function plot_solution! end

"""
    plot_steps(sol::Solution; columns = 5, panelsize = 260, kw...)

A Makie `Figure` with one panel per assembly step, each showing the pieces
placed so far with the newest one highlighted. Steps where the piece must slide
in from the side say so in the panel title (e.g. "slide in from the left") and
show an arrow. Other keywords are as for [`plot_solution`](@ref).
"""
function plot_steps end

"""
    animate_assembly(sol::Solution, filename; framerate = 1, kw...)

Record an animation (`.gif`, `.mp4`, ...) of the solution being assembled one
piece at a time, and return `filename`. Other keywords are as for
[`plot_solution`](@ref).
"""
function animate_assembly end

"""
    explore(sol::Solution; style = :flat, kw...)
    explore(sols::Vector{<:Solution}; kw...)

An interactive Makie `Figure` for following the assembly of a solution, or
browsing several. Display it with an interactive backend such as GLMakie
(`using GLMakie; explore(sol)`), then drag to turn the view.

- A slider (or ◀ ▶, or the left and right arrow keys) moves through the
  steps; the line beside it says what the step does, e.g. "slide in from the
  left".
- With several solutions, a second slider (or the up and down arrow keys)
  chooses the solution.
- Toggles switch between flat colours and wood, and turn ghosts, slide arrows
  and muting of earlier pieces on and off; "reset view" restores the angle.

Other keywords are passed to [`plot_solution!`](@ref).
"""
function explore end

"""
    instructions(sol::Solution, filename; title = "Assembly instructions", style = :flat,
                 steps_per_page = 6, columns = 2, kw...)

Write printable assembly instructions for `sol` on A4 pages: a title page with
a parts list (each kind of piece drawn on its own, with how many there are)
and the finished puzzle, then the steps, `steps_per_page` to a page in
`columns` columns, each numbered, with a note when a piece must slide in from
the side.

If `filename` ends in `.pdf` the pages go into one PDF, which needs
`using CairoMakie`; otherwise each page is saved as its own image, e.g.
`booklet.png` gives `booklet_1.png`, `booklet_2.png`, .... Returns the file
name(s). Other keywords are as for [`plot_solution`](@ref).
"""
function instructions end

# Internal: the instruction pages as Makie figures (Makie extension).
function instruction_pages end

# Internal: save figures as the pages of one PDF (CairoMakie extension).
function save_pages end
