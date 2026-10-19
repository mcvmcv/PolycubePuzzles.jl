# Counting solutions up to symmetry.
#
# G is the group of symmetries of the target that map solutions to solutions.
# An element acts on target cells and, for a reflection applied to chiral
# pieces that may not be mirrored, also swaps each piece type with its mirror
# twin. To find one solution per G-orbit we
#
# 1. prune: pick a "key" that every solution has (a fixed cell x, or a piece
#    type used exactly once) and keep only the key placements that are minimal
#    in their orbit under the subgroup H of G that preserves the key. Every
#    solution orbit still meets the search space: if S has key placement
#    h(rep) then h⁻¹S has key placement rep.
# 2. filter: accept a solution S only if no image gS that also lies in the
#    pruned search space has a smaller canonical code. Exactly one member of
#    each orbit survives.

struct Sym
    cells::Vector{Int}   # target cell index -> image index
    types::Vector{Int}   # piece type -> image type
end

# Piece type permutation induced by reflecting all pieces, or nothing if the
# piece multiset isn't mirror-closed. Types with no copies are ignored.
function mirror_types(p::Puzzle{N}) where {N}
    rot(s) = orientations(s; reflections = false)
    mirror(s) = Shape{N}([(-c[1], Base.tail(c)...) for c in s.cells])
    σ = collect(eachindex(p.pieces))
    p.reflections && return σ
    forms = [rot(s) for s in p.pieces]
    for t in eachindex(p.pieces)
        last(p.counts[t]) == 0 && continue
        mt = rot(mirror(p.pieces[t]))
        u = findfirst(u -> forms[u] == mt && p.counts[u] == p.counts[t], eachindex(p.pieces))
        u === nothing && return nothing
        σ[t] = u
    end
    σ
end

"""
    solution_symmetries(p::Puzzle, mode::Symbol) -> Vector{Sym}

Non-identity symmetries of the target that map solutions of `p` to solutions.
`mode` is `:none`, `:rotations` (proper rotations only) or `:all`. Under `:all`,
reflections are included if the multiset of pieces is closed under mirroring
(always true when `p.reflections` is set).
"""
function solution_symmetries(p::Puzzle{N}, mode::Symbol) where {N}
    mode in (:none, :rotations, :all) ||
        throw(ArgumentError("symmetry must be :none, :rotations or :all, got :$mode"))
    syms = Sym[]
    cells = p.target.cells
    (mode === :none || isempty(cells)) && return syms
    index = Dict(c => i for (i, c) in enumerate(cells))
    lo, _ = bounds(cells)
    id = collect(eachindex(p.pieces))
    σ = mode === :all ? mirror_types(p) : nothing
    for (perm, signs) in symmetries(N; reflections = true)
        proper = parity(perm) * prod(signs; init = 1) == 1
        types = proper ? id : σ
        types === nothing && continue
        img = [transform(c, perm, signs) for c in cells]
        offset = lo .- first(bounds(img))
        m = Int[]
        for c in img
            i = get(index, c .+ offset, 0)
            i == 0 && break
            push!(m, i)
        end
        length(m) == length(cells) || continue
        m == eachindex(cells) && types == id && continue
        push!(syms, Sym(m, types))
    end
    syms
end

# Image of placement (t, cells) under g, cells sorted into buf.
function image!(buf::Vector{Int}, g::Sym, cells::Vector{Int})
    resize!(buf, length(cells))
    for (k, i) in enumerate(cells)
        buf[k] = g.cells[i]
    end
    sort!(buf)
end

function is_orbit_min(t::Int, cells::Vector{Int}, H::Vector{Sym}, buf::Vector{Int})
    for g in H
        image!(buf, g, cells)
        (g.types[t], buf) < (t, cells) && return false
    end
    true
end

struct Reducer
    syms::Vector{Sym}                      # non-identity symmetries
    keycell::Int                           # key cell index, or 0
    keytype::Int                           # key piece type, or 0
    pre::Vector{Int}                       # pre[g] = cell mapped to keycell by syms[g]
    allowed::Set{Tuple{Int,Vector{Int}}}   # allowed key placements (type, sorted cells)
end

"""
    reduce_rows(p, rows, rowtype, syms) -> (keep::BitVector, reducer::Reducer)

Choose the key giving the largest reduction and mark which placement rows to
keep. `rows[r]` must be sorted.
"""
function reduce_rows(p::Puzzle, rows::Vector{Vector{Int}}, rowtype::Vector{Int}, syms::Vector{Sym})
    keep = trues(length(rows))
    allowed = Set{Tuple{Int,Vector{Int}}}()
    isempty(syms) && return keep, Reducer(syms, 0, 0, Int[], allowed)
    buf = Int[]
    reps(H, cand) = count(r -> is_orbit_min(rowtype[r], rows[r], H, buf), cand)
    best = (factor = 1.0, cell = 0, type = 0, H = syms, rows = Int[])
    # cell key: a cell with the largest stabilizer
    stab = [count(g -> g.cells[x] == x, syms) for x in 1:ncells(p.target)]
    x = argmax(stab)
    if stab[x] > 0
        H = [g for g in syms if g.cells[x] == x]
        cand = [r for r in eachindex(rows) if x in rows[r]]
        f = length(cand) / max(reps(H, cand), 1)
        f > best.factor && (best = (factor = f, cell = x, type = 0, H = H, rows = cand))
    end
    # piece key: a type used exactly once
    for t in eachindex(p.pieces)
        p.counts[t] == 1:1 || continue
        H = [g for g in syms if g.types[t] == t]
        isempty(H) && continue
        cand = [r for r in eachindex(rows) if rowtype[r] == t]
        f = length(cand) / max(reps(H, cand), 1)
        f > best.factor && (best = (factor = f, cell = 0, type = t, H = H, rows = cand))
    end
    for r in best.rows
        if is_orbit_min(rowtype[r], rows[r], best.H, buf)
            push!(allowed, (rowtype[r], rows[r]))
        else
            keep[r] = false
        end
    end
    pre = best.cell == 0 ? Int[] : [findfirst(==(best.cell), g.cells) for g in syms]
    keep, Reducer(syms, best.cell, best.type, pre, allowed)
end

# Per-task leaf filter: is the solution (a list of rows) its orbit's canonical member?
struct Canon
    red::Reducer
    rows::Vector{Vector{Int}}
    rowtype::Vector{Int}
    code0::Vector{Int}
    code::Vector{Int}
    buf::Vector{Int}
end

Canon(red::Reducer, rows, rowtype, n::Int) = Canon(red, rows, rowtype, zeros(Int, n), zeros(Int, n), Int[])

# code[i] identifies the piece covering cell i by its type and smallest cell,
# which determines the solution independently of how copies are ordered.
function encode!(code::Vector{Int}, stack, rows, rowtype)
    n = length(code)
    @inbounds for r in stack
        cells = rows[r]
        v = rowtype[r] * (n + 1) + cells[1]
        for i in cells
            code[i] = v
        end
    end
    code
end

function encode!(code::Vector{Int}, stack, rows, rowtype, g::Sym)
    n = length(code)
    @inbounds for r in stack
        cells = rows[r]
        lo = typemax(Int)
        for i in cells
            lo = min(lo, g.cells[i])
        end
        v = g.types[rowtype[r]] * (n + 1) + lo
        for i in cells
            code[g.cells[i]] = v
        end
    end
    code
end

# Does gS lie in the pruned search space?
function key_allowed(c::Canon, stack, k::Int)
    red = c.red
    red.keycell == 0 && red.keytype == 0 && return true
    g = red.syms[k]
    for r in stack
        t = c.rowtype[r]
        hit = red.keytype != 0 ? g.types[t] == red.keytype : red.pre[k] in c.rows[r]
        hit || continue
        image!(c.buf, g, c.rows[r])
        return (g.types[t], c.buf) in red.allowed
    end
    false
end

function iscanonical(c::Canon, stack)
    isempty(c.red.syms) && return true
    encode!(c.code0, stack, c.rows, c.rowtype)
    for k in eachindex(c.red.syms)
        key_allowed(c, stack, k) || continue
        encode!(c.code, stack, c.rows, c.rowtype, c.red.syms[k]) < c.code0 && return false
    end
    true
end
