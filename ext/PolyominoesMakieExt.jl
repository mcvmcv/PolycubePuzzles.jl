module PolyominoesMakieExt

using Polyominoes
using Polyominoes: Solution, Placement, neighbors, bounds
using Makie

import Polyominoes: plot_solution, plot_solution!, plot_steps, animate_assembly

# Categorical palette in fixed slot order (blue, orange, aqua, yellow, magenta,
# green, violet, red). Pieces get slots by adjacency colouring, so touching
# pieces always differ; the edge outlines keep pieces distinguishable without
# relying on colour alone.
const PALETTE = Makie.to_color.(["#2a78d6", "#eb6834", "#1baf7a", "#eda100",
                                 "#e87ba4", "#008300", "#6250d6", "#e34948"])
const MUTED_TOWARD = Makie.to_color("#e4e3df")
const INK = Makie.to_color("#2b2b29")
const FRAME = Makie.to_color("#b8b7b1")

blend(a, b, t) = Makie.RGBf((1 - t) * Makie.red(a) + t * Makie.red(b),
                            (1 - t) * Makie.green(a) + t * Makie.green(b),
                            (1 - t) * Makie.blue(a) + t * Makie.blue(b))

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

shade(c, f) = Makie.RGBf(f * Makie.red(c), f * Makie.green(c), f * Makie.blue(c))

# Append the exterior faces of a polycube to the mesh buffers (V vertices, C
# vertex colours, F triangles). Outlines are drawn into the mesh as dark strips
# of width w along the piece's silhouette edges (edges not shared by two
# coplanar faces of the piece), so they are depth-sorted with the faces even on
# backends without a depth buffer.
function add_piece!(V, C, F, cells::Vector{NTuple{3,Int}}, color, w)
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
    us = (0.0f0, Float32(w), 1.0f0 - Float32(w), 1.0f0)
    for (c, d, s) in faces
        q = face_corners(c, d, s)
        fill = shade(color, FACE_SHADE[(d, s)])
        out(k) = edgekey(q[k], q[mod1(k + 1, 4)], d, s) in outline
        corner(k) = (Tuple(q[k]), d, s) in ends
        # 3x3 grid on the face: corners, edge strips, centre
        inked = ((corner(1), out(1), corner(2)),     # v = 0 row: q1 -> q2
                 (out(4), false, out(2)),
                 (corner(4), out(3), corner(3)))     # v = 1 row: q4 -> q3
        P(u, v) = q[1] + u * (q[2] - q[1]) + v * (q[4] - q[1])
        for j in 1:3, i in 1:3
            col = inked[j][i] ? INK : fill
            o = length(V)
            push!(V, P(us[i], us[j]), P(us[i+1], us[j]), P(us[i+1], us[j+1]), P(us[i], us[j+1]))
            push!(C, col, col, col, col)
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

function piece_colors(sol, step, order, coloring, colors, highlight, muted)
    shown = order[1:step]
    newest = step > 0 ? order[step] : 0
    map(shown) do k
        base = colors[mod1(coloring[k], length(colors))]
        highlight && muted && k != newest ? blend(base, MUTED_TOWARD, 0.72) : base
    end
end

function plot_solution!(ax, sol::Solution{3}; step::Integer = length(sol),
                        order = assembly_order(sol), coloring = piece_coloring(sol),
                        colors = PALETTE, highlight::Bool = step < length(sol),
                        muted::Bool = true, frame::Bool = true, linewidth = 0.035)
    lo, hi = bounds(reduce(vcat, [pl.cells for pl in sol]))
    frame && linesegments!(ax, frame_3d(lo, hi); color = FRAME, linewidth = 0.8)
    step == 0 && return ax
    cols = piece_colors(sol, step, order, coloring, colors, highlight, muted)
    V, C, F = Point3f[], Makie.RGBf[], Makie.GLTriangleFace[]
    for (i, k) in enumerate(order[1:step])
        newest = highlight && i == step
        add_piece!(V, C, F, sol.placements[k].cells, cols[i], newest ? 2.2 * linewidth : linewidth)
    end
    mesh!(ax, V, F; color = C, shading = NoShading)
    ax
end

function plot_solution!(ax, sol::Solution{2}; step::Integer = length(sol),
                        order = assembly_order(sol), coloring = piece_coloring(sol),
                        colors = PALETTE, highlight::Bool = step < length(sol),
                        muted::Bool = true, frame::Bool = true, linewidth = 1.2)
    lo, hi = bounds(reduce(vcat, [pl.cells for pl in sol]))
    if frame
        x0, y0 = lo .- 1
        x1, y1 = hi
        lines!(ax, Point2f[(x0, y0), (x1, y0), (x1, y1), (x0, y1), (x0, y0)];
               color = FRAME, linewidth = 0.8)
    end
    cols = piece_colors(sol, step, order, coloring, colors, highlight, muted)
    for (i, k) in enumerate(order[1:step])
        cells = sol.placements[k].cells
        poly!(ax, [Rect2f(c[1] - 1, c[2] - 1, 1, 1) for c in cells]; color = cols[i],
              strokecolor = cols[i], strokewidth = 0.75)
        newest = highlight && i == step
        linesegments!(ax, outline_2d(cells); color = INK,
                      linewidth = newest ? 2.5 * linewidth : linewidth)
    end
    ax
end

function new_axis(pos, ::Solution{3}; title = "", azimuth = 1.15π, elevation = 0.18π, kw...)
    ax = Axis3(pos; aspect = :data, azimuth, elevation, title, kw...)
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

function plot_solution(sol::Solution; size = (600, 600), title = "", kw...)
    axkw, plotkw = split_kw(kw)
    fig = Figure(; size)
    ax = new_axis(fig[1, 1], sol; title, axkw...)
    plot_solution!(ax, sol; plotkw...)
    fig
end

function plot_steps(sol::Solution; order = assembly_order(sol), columns::Integer = 5,
                    panelsize = 260, kw...)
    axkw, plotkw = split_kw(kw)
    n = length(sol)
    rows = cld(n, columns)
    fig = Figure(; size = (columns * panelsize, rows * (panelheight(sol, panelsize) + 30)))
    for k in 1:n
        ax = new_axis(fig[fld1(k, columns), mod1(k, columns)], sol;
                      title = "Step $k", titlealign = :left, titlesize = 14,
                      titlefont = :regular, axkw...)
        plot_solution!(ax, sol; step = k, order, highlight = true, plotkw...)
    end
    fig
end

function animate_assembly(sol::Solution, filename::AbstractString; order = assembly_order(sol),
                          framerate::Integer = 1, size = (600, 600), kw...)
    axkw, plotkw = split_kw(kw)
    fig = Figure(; size)
    ax = new_axis(fig[1, 1], sol; axkw...)
    n = length(sol)
    record(fig, filename, 1:n; framerate) do k
        empty!(ax)
        ax.title = k < n ? "Step $k of $n" : "Done"
        plot_solution!(ax, sol; step = k, order, highlight = k < n, plotkw...)
    end
    filename
end

end
