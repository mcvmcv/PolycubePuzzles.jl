module PolycubePuzzlesMakieExt

using PolycubePuzzles
using PolycubePuzzles: Solution, Placement, Insertion, neighbors, bounds, sightlines, insertion
using Makie

import PolycubePuzzles: plot_solution, plot_solution!, plot_steps, animate_assembly, explore,
                        instructions, instruction_pages

# Categorical palette in fixed slot order (blue, orange, aqua, yellow, magenta,
# green, violet, red). Pieces get slots by adjacency colouring, so touching
# pieces always differ; the edge outlines keep pieces distinguishable without
# relying on colour alone.
const PALETTE = Makie.to_color.(["#2a78d6", "#eb6834", "#1baf7a", "#eda100",
                                 "#e87ba4", "#008300", "#6250d6", "#e34948"])
# Wood tones for style = :wood, alternating light and dark so that touching
# pieces (which get different slots) contrast: maple, mahogany, oak, walnut,
# ash, cherry, beech, padauk.
const WOODS = Makie.to_color.(["#e2c08d", "#8c4a32", "#c9a165", "#6e4a2f",
                               "#eedcb3", "#b36b3f", "#d4a373", "#a4502d"])
const MUTED_TOWARD = Makie.to_color("#e4e3df")
const WOOD_MUTED_TOWARD = Makie.to_color("#ebe8e2")
const WOOD_MUTED_GRAIN = 0.35
const INK = Makie.to_color("#2b2b29")
const WOOD_INK = Makie.to_color("#3b2a1d")
const FRAME = Makie.to_color("#b8b7b1")

blend(a, b, t) = Makie.RGBf((1 - t) * Makie.red(a) + t * Makie.red(b),
                            (1 - t) * Makie.green(a) + t * Makie.green(b),
                            (1 - t) * Makie.blue(a) + t * Makie.blue(b))

shade(c, f) = Makie.RGBf(min(1, f * Makie.red(c)), min(1, f * Makie.green(c)), min(1, f * Makie.blue(c)))

# Deterministic pseudo-random number in [0, 1) for piece `seed`, draw `i`.
rnd(seed, i) = (hash((seed, i, :wood)) % 0x100000) / 0x100000

# Colour of a piece at a point. Wood is a solid texture: growth rings around a
# "log" axis running along the piece's longest dimension, so the grain follows
# the piece and wraps continuously round its corners. `grain` scales how dark
# the rings are.
function painter(style::Symbol, cells::Vector{NTuple{N,Int}}, base, seed; grain = 1.0) where {N}
    style === :flat && return p -> base
    style === :wood || throw(ArgumentError("style must be :flat or :wood, got :$style"))
    lo, hi = bounds(cells)
    a = argmax(collect(hi .- lo))
    centre = ntuple(N) do i
        i == a && return 0.0
        mid = (lo[i] + hi[i]) / 2 - 0.5
        mid + (rnd(seed, i) < 0.5 ? -1 : 1) * (1.5 + 3 * rnd(seed, i + N))
    end
    freq = 1.3 + 0.7 * rnd(seed, 2N + 1)
    phase = 2π * rnd(seed, 2N + 2)
    light, dark = shade(base, 1.06), shade(base, 1 - 0.34 * grain)
    function (p)
        r2 = 0.0
        for i in 1:N
            i == a || (r2 += (p[i] - centre[i])^2)
        end
        x = p[a]
        r = sqrt(r2) + 0.12 * sin(0.9 * x + phase) + 0.05 * sin(2.7 * x + 2 * phase)
        ring = (0.5 + 0.5 * cos(2π * r * freq))^4       # thin dark latewood bands
        streak = 0.05 * sin(31 * r + 5 * phase) * sin(0.7 * x)
        blend(light, dark, clamp(0.12 + 0.6 * ring + streak, 0, 1))
    end
end

# Exterior faces of a piece: (cell, axis, sign) where the neighbour across the
# face is not part of the same piece.
function exterior_faces(cells::Vector{NTuple{N,Int}}) where {N}
    own = Set(cells)
    [(c, d, s) for c in cells for d in 1:N for s in (-1, 1)
     if !(ntuple(i -> c[i] + (i == d) * s, N) in own)]
end

# Corners of the face of cell c (spanning [c-1, c]) on axis d, side s, wound
# so the normal points outward.
function face_corners(c::NTuple{3,Int}, d::Int, s::Int)
    a = d % 3 + 1
    b = a % 3 + 1
    pt(u, v) = Point3f(ntuple(i -> i == d ? (s > 0 ? c[i] : c[i] - 1) :
                                    i == a ? c[i] - 1 + u : c[i] - 1 + v, 3))
    q = [pt(0, 0), pt(1, 0), pt(1, 1), pt(0, 1)]
    s > 0 ? q : reverse(q)
end

edgekey(a, b, d, s) = (minmax(Tuple(a), Tuple(b))..., d, s)

# Brightness of a face by its outward normal (axis, sign): fixed "lighting" so
# the result doesn't depend on the backend's light model.
const FACE_SHADE = Dict((3, 1) => 1.0, (3, -1) => 0.55, (1, 1) => 0.86,
                        (1, -1) => 0.86, (2, 1) => 0.72, (2, -1) => 0.72)

# Append the exterior faces of a polycube to the mesh buffers (V vertices, C
# vertex colours, F triangles), except those for which skip(cell, axis, sign).
# Outlines are drawn into the mesh as strips of width w along the piece's
# silhouette edges (edges not shared by two coplanar faces of the piece), so
# they are depth-sorted with the faces even on backends without a depth
# buffer. Each face is subdivided nsub times inside its border so that a
# textured paint can vary across it.
function add_piece!(V, C, F, cells::Vector{NTuple{3,Int}}, paint, w, ink;
                    alpha = 1.0f0, skip = (c, d, s) -> false, nsub = 1)
    faces = exterior_faces(cells)
    seen = Dict{Any,Int}()
    for (c, d, s) in faces
        q = face_corners(c, d, s)
        for k in 1:4
            key = edgekey(q[k], q[mod1(k + 1, 4)], d, s)
            seen[key] = get(seen, key, 0) + 1
        end
    end
    outline = Set(k for (k, n) in seen if n == 1)
    ends = Set((p, k[3], k[4]) for k in outline for p in (k[1], k[2]))
    w = Float32(w)
    us = Float32[0; w; [w + (1 - 2w) * i / nsub for i in 1:nsub-1]; 1 - w; 1]
    m = length(us) - 1
    inkc = Makie.RGBAf(ink, alpha)
    for (c, d, s) in faces
        skip(c, d, s) && continue
        q = face_corners(c, d, s)
        f = FACE_SHADE[(d, s)]
        out(k) = edgekey(q[k], q[mod1(k + 1, 4)], d, s) in outline
        corner(k) = (Tuple(q[k]), d, s) in ends
        # border cells of the grid are outline strips where the edge is a silhouette
        function inked(i, j)
            (i == 1 || i == m) && (j == 1 || j == m) &&
                return corner(i == 1 ? (j == 1 ? 1 : 4) : (j == 1 ? 2 : 3))
            j == 1 && return out(1)
            i == m && return out(2)
            j == m && return out(3)
            i == 1 && return out(4)
            false
        end
        P(u, v) = q[1] + u * (q[2] - q[1]) + v * (q[4] - q[1])
        for j in 1:m, i in 1:m
            pts = (P(us[i], us[j]), P(us[i+1], us[j]), P(us[i+1], us[j+1]), P(us[i], us[j+1]))
            o = length(V)
            push!(V, pts...)
            if inked(i, j)
                push!(C, inkc, inkc, inkc, inkc)
            else
                for p in pts
                    push!(C, Makie.RGBAf(shade(paint(p), f), alpha))
                end
            end
            push!(F, Makie.GLTriangleFace(o + 1, o + 2, o + 3), Makie.GLTriangleFace(o + 1, o + 3, o + 4))
        end
    end
end

function outline_2d(cells::Vector{NTuple{2,Int}})
    own = Set(cells)
    pts = Point2f[]
    for c in cells, (d, s) in ((1, -1), (1, 1), (2, -1), (2, 1))
        ntuple(i -> c[i] + (i == d) * s, 2) in own && continue
        x0, y0 = c[1] - 1, c[2] - 1
        if d == 1
            x = s > 0 ? x0 + 1 : x0
            push!(pts, Point2f(x, y0), Point2f(x, y0 + 1))
        else
            y = s > 0 ? y0 + 1 : y0
            push!(pts, Point2f(x0, y), Point2f(x0 + 1, y))
        end
    end
    pts
end

# Subdivided squares for a 2D piece, coloured by paint at each vertex.
function add_cells_2d!(V, C, F, cells, paint, nsub)
    for c in cells, j in 1:nsub, i in 1:nsub
        x0 = c[1] - 1 + (i - 1) / nsub
        y0 = c[2] - 1 + (j - 1) / nsub
        x1, y1 = x0 + 1 / nsub, y0 + 1 / nsub
        o = length(V)
        for p in (Point2f(x0, y0), Point2f(x1, y0), Point2f(x1, y1), Point2f(x0, y1))
            push!(V, p)
            push!(C, paint(p))
        end
        push!(F, Makie.GLTriangleFace(o + 1, o + 2, o + 3), Makie.GLTriangleFace(o + 1, o + 3, o + 4))
    end
end

function frame_3d(lo, hi)
    x0, y0, z0 = lo .- 1
    x1, y1, z1 = hi
    corners = [Point3f(x, y, z) for x in (x0, x1), y in (y0, y1), z in (z0, z1)]
    pts = Point3f[]
    for i in eachindex(corners), j in eachindex(corners)
        i < j || continue
        a, b = corners[i], corners[j]
        count(k -> a[k] != b[k], 1:3) == 1 && push!(pts, a, b)
    end
    pts
end

function piece_colors(step, order, coloring, colors, highlight, muted, style)
    newest = step > 0 ? order[step] : 0
    # muted wood is bleached toward a cool grey (and its grain faded, see
    # WOOD_MUTED_GRAIN), so the newest piece is the only warm, grainy one
    toward, t = style === :wood ? (WOOD_MUTED_TOWARD, 0.7) : (MUTED_TOWARD, 0.72)
    map(order[1:step]) do k
        base = colors[mod1(coloring[k], length(colors))]
        highlight && muted && k != newest ? blend(base, toward, t) : base
    end
end

viewdir(ax::Axis3) = (az = ax.azimuth[]; el = ax.elevation[];
                      (cos(az) * cos(el), sin(az) * cos(el), sin(el)))
rightdir(ax::Axis3) = (az = ax.azimuth[]; (-sin(az), cos(az), 0.0))

# Assembly order for the axis's viewpoint: in 3D, build from the back and left
# so each new piece goes in front of the ones already placed.
function view_order(ax, sol::Solution)
    ax isa Axis3 || return assembly_order(sol)
    assembly_order(sol; view = viewdir(ax), right = rightdir(ax))
end

# Where a sliding piece comes from, in the viewer's terms.
function from_words(ins::Insertion{N}, ax) where {N}
    ins.kind === :path && return "slide in along the arrow"
    ins.kind === :blocked && return "can't be slid in"
    ins.kind === :slide || return ""
    from = .-ins.moves[1]
    if N == 3 && ax isa Axis3
        r, h = rightdir(ax), viewdir(ax)
        h = (h[1], h[2], 0.0)
        dirs = ("right" => sum(from .* r), "left" => -sum(from .* r),
                "front" => sum(from .* h), "back" => -sum(from .* h), "above" => float(from[3]))
    else
        dirs = ("right" => float(from[1]), "left" => -float(from[1]), "above" => float(from[N]))
    end
    "slide in from the " * first(argmax(last, dirs))
end

centroid(cells) = reduce((a, b) -> a .+ b, (Float32.(c) .- 0.5f0 for c in cells)) ./ length(cells)

# Arrow along the slide(s) that bring a piece into place, ending just short of it.
function draw_slide!(ax, cells::Vector{NTuple{N,Int}}, ins::Insertion{N}, color) where {N}
    ins.kind in (:slide, :path) || return
    P = N == 3 ? Point3f : Point2f
    pts = [P(centroid(cells))]
    for m in Iterators.reverse(ins.moves)
        pushfirst!(pts, pts[1] - P(m))
    end
    # a straight slide only needs a short arrow
    if ins.kind === :slide
        d = pts[2] - pts[1]
        pts[1] = pts[2] - d / sqrt(sum(abs2, d)) * min(sqrt(sum(abs2, d)), 2.5f0)
    end
    tail = pts[end] - pts[end-1]
    len = sqrt(sum(abs2, tail))
    tipend = pts[end] - tail / len * 0.6f0
    length(pts) > 2 && lines!(ax, pts[1:end-1]; color, linewidth = 3)
    if N == 3
        arrows3d!(ax, [pts[end-1]], [Vec3f(tipend - pts[end-1])]; color,
                  shaftradius = 0.06, tipradius = 0.18, tiplength = 0.4, markerscale = 1)
    else
        arrows2d!(ax, [pts[end-1]], [Vec2f(tipend - pts[end-1])]; color,
                  shaftwidth = 3, tipwidth = 14, tiplength = 14)
    end
end

function plot_solution!(ax, sol::Solution{3}; step::Integer = length(sol),
                        order = view_order(ax, sol), coloring = piece_coloring(sol),
                        style::Symbol = :flat, colors = style === :wood ? WOODS : PALETTE,
                        highlight::Bool = step < length(sol), muted::Bool = true,
                        frame::Bool = true, linewidth = style === :wood ? 0.025 : 0.035,
                        ghost::Bool = true, arrows::Bool = true, cullbackfaces::Bool = true)
    lo, hi = bounds(reduce(vcat, [pl.cells for pl in sol]))
    # fixed limits, so every step (and animation frame) has the same framing
    limits!(ax, lo[1] - 1, hi[1], lo[2] - 1, hi[2], lo[3] - 1, hi[3])
    frame && linesegments!(ax, frame_3d(lo, hi); color = FRAME, linewidth = 0.8)
    step == 0 && return ax
    shown = order[1:step]
    cols = piece_colors(step, order, coloring, colors, highlight, muted, style)
    ink = style === :wood ? WOOD_INK : INK
    # pieces hiding the newest one from the viewer are drawn as faint ghosts
    hiders = Set{Int}()
    if highlight && ghost && ax isa Axis3
        owner = Dict(c => k for k in shown for c in sol.placements[k].cells)
        _, _, hiders = sightlines(owner, order[step], o -> true, viewdir(ax))
    end
    # faces against an opaque piece, or turned away from the viewer, can't be
    # seen (but an interactive view can be turned, so keep those)
    opaque = Set(c for k in shown if !(k in hiders) for c in sol.placements[k].cells)
    v = ax isa Axis3 && cullbackfaces ? viewdir(ax) : nothing
    skip(c, d, s) = ntuple(i -> c[i] + (i == d) * s, 3) in opaque ||
                    (v !== nothing && s * v[d] <= 0)
    V, C, F = Point3f[], Makie.RGBAf[], Makie.GLTriangleFace[]
    for (i, k) in enumerate(shown)
        newest = highlight && i == step
        cells = sol.placements[k].cells
        faded = highlight && muted && !newest
        add_piece!(V, C, F, cells,
                   painter(style, cells, cols[i], k; grain = faded ? WOOD_MUTED_GRAIN : 1.0),
                   newest ? (style === :wood ? 3.2 : 2.2) * linewidth : linewidth, ink;
                   alpha = k in hiders ? 0.15f0 : 1.0f0, skip,
                   # ghosts are plain: subdivision seams would show through
                   nsub = style === :wood && !(k in hiders) ? 8 : 1)
    end
    mesh!(ax, V, F; color = C, shading = NoShading, transparency = !isempty(hiders))
    if highlight && arrows
        k = order[step]
        draw_slide!(ax, sol.placements[k].cells, insertion(sol, k, order[1:step-1]), ink)
    end
    ax
end

function plot_solution!(ax, sol::Solution{2}; step::Integer = length(sol),
                        order = view_order(ax, sol), coloring = piece_coloring(sol),
                        style::Symbol = :flat, colors = style === :wood ? WOODS : PALETTE,
                        highlight::Bool = step < length(sol), muted::Bool = true,
                        frame::Bool = true, linewidth = 1.2, arrows::Bool = true)
    lo, hi = bounds(reduce(vcat, [pl.cells for pl in sol]))
    limits!(ax, lo[1] - 1.1, hi[1] + 0.1, lo[2] - 1.1, hi[2] + 0.1)
    if frame
        x0, y0 = lo .- 1
        x1, y1 = hi
        lines!(ax, Point2f[(x0, y0), (x1, y0), (x1, y1), (x0, y1), (x0, y0)];
               color = FRAME, linewidth = 0.8)
    end
    step == 0 && return ax
    cols = piece_colors(step, order, coloring, colors, highlight, muted, style)
    ink = style === :wood ? WOOD_INK : INK
    for (i, k) in enumerate(order[1:step])
        cells = sol.placements[k].cells
        if style === :flat
            poly!(ax, [Rect2f(c[1] - 1, c[2] - 1, 1, 1) for c in cells]; color = cols[i],
                  strokecolor = cols[i], strokewidth = 0.75)
        else
            V, C, F = Point2f[], Makie.RGBf[], Makie.GLTriangleFace[]
            faded = highlight && muted && i != step
            add_cells_2d!(V, C, F, cells,
                          painter(style, cells, cols[i], k; grain = faded ? WOOD_MUTED_GRAIN : 1.0), 8)
            mesh!(ax, V, F; color = C, shading = NoShading)
        end
        newest = highlight && i == step
        linesegments!(ax, outline_2d(cells); color = ink,
                      linewidth = newest ? 2.5 * linewidth : linewidth)
    end
    if highlight && arrows
        k = order[step]
        draw_slide!(ax, sol.placements[k].cells, insertion(sol, k, order[1:step-1]), ink)
    end
    ax
end

function new_axis(pos, ::Solution{3}; title = "", azimuth = 1.15π, elevation = 0.18π, kw...)
    # unclipped, so slide arrows starting outside the box are drawn
    ax = Axis3(pos; aspect = :data, azimuth, elevation, title, clip = false, kw...)
    hidedecorations!(ax)
    hidespines!(ax)
    ax
end

function new_axis(pos, ::Solution{2}; title = "", kw...)
    ax = Axis(pos; aspect = DataAspect(), title, kw...)
    hidedecorations!(ax)
    hidespines!(ax)
    ax
end

panelheight(::Solution{3}, w) = w
function panelheight(sol::Solution{2}, w)
    lo, hi = bounds(reduce(vcat, [pl.cells for pl in sol]))
    round(Int, w * (hi[2] - lo[2] + 1) / (hi[1] - lo[1] + 1))
end

const AXIS_KEYS = (:azimuth, :elevation)

split_kw(kw) = (; (k => v for (k, v) in pairs(kw) if k in AXIS_KEYS)...),
               (; (k => v for (k, v) in pairs(kw) if !(k in AXIS_KEYS))...)

function step_title(sol, order, k, ax; prefix = "Step $k")
    words = from_words(insertion(sol, order[k], order[1:k-1]), ax)
    isempty(words) ? prefix : "$prefix: $words"
end

function plot_solution(sol::Solution; size = (600, 600), title = "", kw...)
    axkw, plotkw = split_kw(kw)
    fig = Figure(; size)
    ax = new_axis(fig[1, 1], sol; title, axkw...)
    plot_solution!(ax, sol; plotkw...)
    fig
end

function plot_steps(sol::Solution; order = nothing, columns::Integer = 5,
                    panelsize = 260, kw...)
    axkw, plotkw = split_kw(kw)
    n = length(sol)
    rows = cld(n, columns)
    fig = Figure(; size = (columns * panelsize, rows * (panelheight(sol, panelsize) + 30)))
    for k in 1:n
        ax = new_axis(fig[fld1(k, columns), mod1(k, columns)], sol;
                      titlealign = :left, titlesize = 14, titlefont = :regular, axkw...)
        order === nothing && (order = view_order(ax, sol))
        ax.title = step_title(sol, order, k, ax)
        plot_solution!(ax, sol; step = k, order, highlight = true, plotkw...)
    end
    fig
end

function animate_assembly(sol::Solution, filename::AbstractString; order = nothing,
                          framerate::Integer = 1, size = (600, 600), kw...)
    axkw, plotkw = split_kw(kw)
    fig = Figure(; size)
    ax = new_axis(fig[1, 1], sol; axkw...)
    order === nothing && (order = view_order(ax, sol))
    n = length(sol)
    record(fig, filename, 1:n; framerate) do k
        empty!(ax)
        ax.title = k < n ? step_title(sol, order, k, ax; prefix = "Step $k of $n") : "Done"
        plot_solution!(ax, sol; step = k, order, highlight = k < n, plotkw...)
    end
    filename
end

# Keywords that only the 3D plot takes.
dimkw(::Solution{3}; ghost, kw...) = (; ghost, cullbackfaces = false, kw...)
dimkw(::Solution{2}; ghost, kw...) = (; kw...)

function explore(sols::AbstractVector{<:Solution}; style::Symbol = :flat, size = (900, 820),
                 azimuth = 1.15π, elevation = 0.18π, kw...)
    isempty(sols) && throw(ArgumentError("no solutions to explore"))
    sol1 = first(sols)
    n = length(sol1)
    fig = Figure(; size)
    ax = sol1 isa Solution{3} ? new_axis(fig[1, 1], sol1; azimuth, elevation) : new_axis(fig[1, 1], sol1)
    controls = GridLayout(fig[2, 1]; tellwidth = false)

    prev = Button(controls[1, 1]; label = "◀", width = 40)
    stepslider = Slider(controls[1, 2]; range = 0:n, startvalue = n, width = 420)
    next = Button(controls[1, 3]; label = "▶", width = 40)
    status = Label(controls[1, 4], ""; halign = :left, width = 320)

    many = length(sols) > 1
    solslider = many ? Slider(controls[2, 2]; range = 1:length(sols), startvalue = 1, width = 420) : nothing
    if many
        Label(controls[2, 1], "Solution")
        sollabel = Label(controls[2, 3:4], lift(i -> "$i of $(length(sols))", solslider.value);
                         halign = :left)
    end

    toggles = GridLayout(controls[3, 1:4])
    function toggle(col, text, on)
        t = Toggle(toggles[1, 2col-1]; active = on)
        Label(toggles[1, 2col], text; halign = :left)
        t
    end
    wood = toggle(1, "wood", style === :wood)
    ghosts = toggle(2, "ghosts", true)
    arrows = toggle(3, "arrows", true)
    muted = toggle(4, "mute earlier pieces", true)
    reset = Button(toggles[1, 9]; label = "reset view")

    # the assembly order depends on the view it is built for; keep it per solution
    orders = Dict{Int,Vector{Int}}()
    order_for(i) = get!(() -> view_order(ax, sols[i]), orders, i)
    current() = many ? solslider.value[] : 1

    function redraw()
        i = current()
        sol = sols[i]
        k = stepslider.value[]
        order = order_for(i)
        empty!(ax)
        status.text = k == 0 ? "Empty" : k == n ? "Complete: $n pieces" :
                      step_title(sol, order, k, ax; prefix = "Step $k of $n")
        plot_solution!(ax, sol; dimkw(sol; step = k, order, highlight = 0 < k < n,
                                      style = wood.active[] ? :wood : :flat,
                                      ghost = ghosts.active[], arrows = arrows.active[],
                                      muted = muted.active[], kw...)...)
    end

    onany((_...) -> redraw(), stepslider.value, wood.active, ghosts.active, arrows.active, muted.active)
    many && on(_ -> redraw(), solslider.value)
    on(_ -> set_close_to!(stepslider, stepslider.value[] - 1), prev.clicks)
    on(_ -> set_close_to!(stepslider, stepslider.value[] + 1), next.clicks)
    on(reset.clicks) do _
        if ax isa Axis3
            ax.azimuth[] = azimuth
            ax.elevation[] = elevation
        end
    end
    on(events(fig).keyboardbutton) do event
        event.action in (Keyboard.press, Keyboard.repeat) || return
        event.key == Keyboard.left && set_close_to!(stepslider, stepslider.value[] - 1)
        event.key == Keyboard.right && set_close_to!(stepslider, stepslider.value[] + 1)
        if many
            event.key == Keyboard.down && set_close_to!(solslider, solslider.value[] - 1)
            event.key == Keyboard.up && set_close_to!(solslider, solslider.value[] + 1)
        end
    end
    redraw()
    fig
end

explore(sol::Solution; kw...) = explore([sol]; kw...)

# Printable instructions: A4 pages in PDF points (pt_per_unit = 1).
const A4 = (595, 842)

piece_solution(sol::Solution{N}, t, cells) where {N} =
    Solution{N}([Placement{N}(t, PolycubePuzzles.normalize(PolycubePuzzles.Shape(cells)).cells)])

function instruction_pages(sol::Solution{N}; title = "Assembly instructions",
                           style::Symbol = :flat, steps_per_page::Integer = 6,
                           columns::Integer = 2, pagesize = A4, azimuth = 1.15π,
                           elevation = 0.18π, colors = style === :wood ? WOODS : PALETTE,
                           coloring = piece_coloring(sol), kw...) where {N}
    n = length(sol)
    axkw = N == 3 ? (; azimuth, elevation) : (;)
    # small 3D panels: hidden decorations still reserve room unless told not to
    panelkw = N == 3 ? (; axkw..., protrusions = 0) : axkw
    kw = (; colors, coloring, kw...)
    pages = Figure[]
    npages = 1 + cld(n, steps_per_page)
    footer(fig, page) = Label(fig[end+1, :], "$page / $npages"; fontsize = 9,
                              color = :gray40, tellwidth = false)

    # title page: the parts, then the finished puzzle
    fig = Figure(; size = pagesize, figure_padding = 36)
    Label(fig[1, 1], title; fontsize = 24, font = :bold, halign = :left, tellwidth = false)
    types = sort!(unique(pl.piece for pl in sol))
    counts = Dict(t => count(pl -> pl.piece == t, sol.placements) for t in types)
    Label(fig[2, 1], "$n pieces, $n steps"; fontsize = 12, halign = :left, tellwidth = false)
    Label(fig[3, 1], "Pieces"; fontsize = 15, font = :bold, halign = :left, tellwidth = false)
    parts = GridLayout(fig[4, 1]; tellwidth = false)
    pcols = min(length(types), 4)
    for (i, t) in enumerate(types)
        cell = parts[fld1(i, pcols), mod1(i, pcols)] = GridLayout()
        # drawn in the colour its first copy has in the steps
        k = findfirst(pl -> pl.piece == t, sol.placements)
        ps = piece_solution(sol, t, sol.placements[k].cells)
        ax = new_axis(cell[1, 1], ps; panelkw...)
        plot_solution!(ax, ps; colors = [colors[mod1(coloring[k], length(colors))]], style,
                       frame = false, highlight = false, coloring = [1])
        Label(cell[2, 1], "× $(counts[t])"; fontsize = 14, tellwidth = false)
    end
    Label(fig[5, 1], "Finished"; fontsize = 15, font = :bold, halign = :left, tellwidth = false)
    ax = new_axis(fig[6, 1], sol; axkw...)
    order = view_order(ax, sol)
    plot_solution!(ax, sol; order, style, kw...)
    rowsize!(fig.layout, 4, Relative(0.3))
    rowsize!(fig.layout, 6, Relative(0.4))
    footer(fig, 1)
    push!(pages, fig)

    # the steps, steps_per_page to a page
    rows = cld(steps_per_page, columns)
    for (p, ks) in enumerate(Iterators.partition(1:n, steps_per_page))
        fig = Figure(; size = pagesize, figure_padding = 30)
        for (j, k) in enumerate(ks)
            cell = fig[fld1(j, columns), mod1(j, columns)] = GridLayout()
            Label(cell[1, 1], string(k); fontsize = 22, font = :bold, halign = :left,
                  tellwidth = false)
            words = from_words(insertion(sol, order[k], order[1:k-1]), ax)
            Label(cell[1, 2], isempty(words) ? "" : words; fontsize = 11, halign = :right,
                  tellwidth = false)
            sax = new_axis(cell[2, 1:2], sol; panelkw...)
            plot_solution!(sax, sol; step = k, order, highlight = true, style, kw...)
            rowsize!(cell, 2, Relative(0.88))
        end
        # keep panels the same size on a part-filled last page
        for j in length(ks)+1:steps_per_page
            Box(fig[fld1(j, columns), mod1(j, columns)]; visible = false)
        end
        footer(fig, p + 1)
        push!(pages, fig)
    end
    pages
end

function instructions(sol::Solution, filename::AbstractString; kw...)
    pages = instruction_pages(sol; kw...)
    base, ext = splitext(filename)
    if lowercase(ext) == ".pdf"
        isnothing(Base.get_extension(PolycubePuzzles, :PolycubePuzzlesCairoMakieExt)) &&
            error("writing a PDF needs CairoMakie: run `using CairoMakie` first")
        PolycubePuzzles.save_pages(filename, pages)
        return filename
    end
    files = String[]
    for (i, fig) in enumerate(pages)
        push!(files, "$(base)_$(i)$(ext)")
        save(files[end], fig)
    end
    files
end

end
