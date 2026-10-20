# Identifying solutions that differ only by a two-piece swap: two touching
# pieces whose cells together can be filled by the same two piece types in
# another way (for example two Y pentacubes side by side, nubs together, which
# can trade nubs). The class of a solution is everything reachable from it by
# such swaps and, when symmetry reduction is on, by the symmetries in use; it
# is identified by the smallest code (as in `encode!`) among its members.

struct Swapper
    n::Int
    syms::Vector{Sym}
    types::Vector{Int}                       # placement -> piece type
    cells::Vector{Vector{Int}}               # placement -> sorted cell indices
    bycell::Vector{Vector{Int}}              # cell -> placements covering it
    known::Set{Tuple{Int,Vector{Int}}}       # every placement as (type, cells)
    neighbours::Vector{Vector{Int}}          # cell -> adjacent target cells
end

function Swapper(p::Puzzle{N}, syms::Vector{Sym}) where {N}
    pls, rows = placement_rows(p)
    foreach(sort!, rows)
    types = [pl.piece for pl in pls]
    n = ncells(p.target)
    bycell = [Int[] for _ in 1:n]
    for (r, cells) in enumerate(rows), i in cells
        push!(bycell[i], r)
    end
    index = Dict(c => i for (i, c) in enumerate(p.target.cells))
    neighbours = map(p.target.cells) do c
        [index[a] for d in 1:N for s in (-1, 1)
         for a in (ntuple(i -> c[i] + (i == d) * s, N),) if haskey(index, a)]
    end
    Swapper(n, syms, types, rows, bycell, Set(zip(types, rows)), neighbours)
end

const Pieces = Vector{Tuple{Int,Vector{Int}}}   # a solution as sorted (type, cells)

# Solutions one two-piece swap away from `s`.
function swap_neighbours(sw::Swapper, s::Pieces)
    owner = zeros(Int, sw.n)
    for (k, (_, cells)) in enumerate(s), i in cells
        owner[i] = k
    end
    out = Pieces[]
    done = Set{Tuple{Int,Int}}()
    for (k, (_, cells)) in enumerate(s), i in cells, a in sw.neighbours[i]
        l = owner[a]
        l > k && (k, l) ∉ done || continue
        push!(done, (k, l))
        (tk, ck), (tl, cl) = s[k], s[l]
        u = sort!(vcat(ck, cl))
        inu = falses(sw.n)
        inu[u] .= true
        for r in sw.bycell[u[1]]
            t = sw.types[r]
            (t == tk || t == tl) && all(i -> inu[i], sw.cells[r]) || continue
            rest = [i for i in u if !(i in sw.cells[r])]
            other = t == tk ? tl : tk
            (other, rest) in sw.known || continue
            pair = sort!([(t, sw.cells[r]), (other, rest)])
            pair == sort!([s[k], s[l]]) && continue
            push!(out, sort!([[s[m] for m in eachindex(s) if m != k && m != l]; pair]))
        end
    end
    out
end

function code(sw::Swapper, s::Pieces, g::Union{Sym,Nothing})
    c = zeros(Int, sw.n)
    for (t, cells) in s
        lo = g === nothing ? cells[1] : minimum(i -> g.cells[i], cells)
        v = (g === nothing ? t : g.types[t]) * (sw.n + 1) + lo
        for i in cells
            c[g === nothing ? i : g.cells[i]] = v
        end
    end
    c
end

"""
    class_code(sw::Swapper, s::Pieces) -> (code, members)

`code` is the same for every solution in the class of `s`; `members` are the
solutions reachable from `s` by swaps alone, which all share it.
"""
function class_code(sw::Swapper, s::Pieces)
    seen = Set([s])
    queue = [s]
    best = code(sw, s, nothing)
    while !isempty(queue)
        m = pop!(queue)
        for g in sw.syms
            best = min(best, code(sw, m, g))
        end
        for m2 in swap_neighbours(sw, m)
            m2 in seen && continue
            push!(seen, m2)
            push!(queue, m2)
            best = min(best, code(sw, m2, nothing))
        end
    end
    best, seen
end

# The classes seen so far, shared by concurrent search tasks. `known` maps
# every solution met while working out a class to its code, so the search
# through a class is done once, not once per member.
struct Classes
    sw::Swapper
    seen::Set{Vector{Int}}
    known::Dict{Pieces,Vector{Int}}
    lock::ReentrantLock
end

Classes(sw::Swapper) = Classes(sw, Set{Vector{Int}}(), Dict{Pieces,Vector{Int}}(), ReentrantLock())

function class_code(cl::Classes, s::Pieces)
    s = sort(s)
    k = @lock cl.lock get(cl.known, s, nothing)
    k === nothing || return k
    k, members = class_code(cl.sw, s)
    @lock cl.lock for m in members
        cl.known[m] = k
    end
    k
end

# Record `code`; true if its class hadn't been seen before.
isnew!(cl::Classes, code) = @lock cl.lock (code in cl.seen ? false : (push!(cl.seen, code); true))
