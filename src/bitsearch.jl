# Bitboard search: the occupied cells are a bitset of W 64-bit words, and each
# placement a precomputed mask. The search always fills the first empty cell
# (in a fixed cell order), trying the placements whose first cell it is: every
# cell before it is filled, so any placement covering it starts there. Placing
# a piece is an AND to test for overlap and an OR to place it.

const Bits{W} = NTuple{W,UInt64}

@inline disjoint(a::Bits{W}, b::Bits{W}) where {W} = iszero(reduce(|, map(&, a, b)))
@inline bor(a::Bits{W}, b::Bits{W}) where {W} = map(|, a, b)

# Index (1-based) of the lowest clear bit, or 0 if all are set.
@inline function first_clear(a::Bits{W}) where {W}
    for i in 1:W
        x = ~a[i]
        x != 0 && return 64 * (i - 1) + trailing_zeros(x) + 1
    end
    0
end

function tobits(::Val{W}, bits) where {W}
    words = zeros(UInt64, W)
    for b in bits
        words[cld(b, 64)] |= UInt64(1) << ((b - 1) % 64)
    end
    Bits{W}(Tuple(words))
end

struct BitSearch{W}
    starts::Vector{UnitRange{Int}}  # cell position -> placements starting there (into masks)
    masks::Vector{Bits{W}}
    row::Vector{Int}                # -> row index in the compiled puzzle
    rowmask::Vector{Bits{W}}        # compiled row index -> its mask
    rowtype::Vector{Int}
    full::Bits{W}                   # bits outside the target are set
    lo::Vector{Int}
    hi::Vector{Int}
    vol::Vector{Int}
end

# Cell order: fill along the target's shortest axes first, with the longest
# axis most significant, e.g. a 10x6 rectangle column by column.
function cell_order(cells::Vector{NTuple{N,Int}}) where {N}
    lo, hi = bounds(cells)
    axes = sortperm(collect(hi .- lo); rev = true, alg = MergeSort)
    sortperm(cells; by = c -> c[axes])
end

function BitSearch(::Val{W}, cells, rows::Vector{Vector{Int}}, rowtype, lo, hi, vol) where {W}
    n = length(cells)
    pos = invperm(cell_order(cells))           # target cell index -> position
    rowpos = [sort!(pos[r]) for r in rows]
    perm = sortperm(eachindex(rows); by = r -> first(rowpos[r]))
    rowmask = [tobits(Val(W), p) for p in rowpos]
    starts = [1:0 for _ in 1:n]
    for (i, r) in enumerate(perm)
        c = first(rowpos[r])
        starts[c] = isempty(starts[c]) ? (i:i) : (starts[c][1]:i)
    end
    full = tobits(Val(W), n+1:64W)
    BitSearch{W}(starts, rowmask[perm], perm, rowmask, rowtype[perm], full, lo, hi, vol)
end

function feasible(B::BitSearch, used::Vector{Int}, remaining::Int)
    need = 0
    cap = 0
    @inbounds for t in eachindex(B.lo)
        need += max(0, B.lo[t] - used[t]) * B.vol[t]
        cap += min(B.hi[t] - used[t], remaining) * B.vol[t]
    end
    need <= remaining <= cap
end

# Calls f(stack) for each solution, or for each partial solution with
# `maxdepth` pieces; stops early if f returns false. Returns false if stopped.
function bsearch!(f, B::BitSearch{W}, occ::Bits{W}, used::Vector{Int}, remaining::Int,
                  stack::Vector{Int}, maxdepth::Int) where {W}
    (remaining == 0 || length(stack) >= maxdepth) && return f(stack) !== false
    c = first_clear(occ)
    @inbounds for i in B.starts[c]
        m = B.masks[i]
        disjoint(m, occ) || continue
        t = B.rowtype[i]
        used[t] < B.hi[t] || continue
        used[t] += 1
        rem = remaining - B.vol[t]
        if feasible(B, used, rem)
            push!(stack, B.row[i])
            go = bsearch!(f, B, bor(occ, m), used, rem, stack, maxdepth)
            pop!(stack)
            if !go
                used[t] -= 1
                return false
            end
        end
        used[t] -= 1
    end
    true
end

# Search from the state reached by placing `prefix` (compiled row indices,
# with types `rowtype`) in a target of `ncells` cells.
function bsearch_from!(f, B::BitSearch{W}, rowtype::Vector{Int}, ncells::Int,
                       prefix, maxdepth::Int = typemax(Int)) where {W}
    occ = B.full
    used = zeros(Int, length(B.lo))
    remaining = ncells
    for r in prefix
        occ = bor(occ, B.rowmask[r])
        used[rowtype[r]] += 1
        remaining -= B.vol[rowtype[r]]
    end
    feasible(B, used, remaining) || return true
    bsearch!(f, B, occ, used, remaining, collect(Int, prefix), maxdepth)
end
