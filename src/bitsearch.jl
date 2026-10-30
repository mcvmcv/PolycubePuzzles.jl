# Bitboard search: the occupied cells are a bitset of W 64-bit words, and each
# placement a precomputed mask. The search always fills the first empty cell
# (in a fixed cell order), trying the placements whose first cell it is: every
# cell before it is filled, so any placement covering it starts there. Placing
# a piece is an AND to test for overlap and an OR to place it. A placement that
# walls off an empty pocket too small for any piece is rejected at once, as
# that pocket would otherwise only be found when the search reached it.

const Bits{W} = NTuple{W,UInt64}

@inline disjoint(a::Bits{W}, b::Bits{W}) where {W} = iszero(reduce(|, map(&, a, b)))
@inline bor(a::Bits{W}, b::Bits{W}) where {W} = map(|, a, b)
@inline isset(a::Bits, i::Int) = @inbounds (a[((i - 1) >> 6) + 1] >> ((i - 1) & 63)) & 1 == 1

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
    # The placements whose first cell is c come in blocks of one piece type,
    # so a type with no copies left is skipped as a whole
    cellblocks::Vector{UnitRange{Int}}  # cell position -> its blocks
    blocktype::Vector{Int}              # block -> piece type
    blockrows::Vector{UnitRange{Int}}   # block -> its placements (into masks)
    masks::Vector{Bits{W}}
    row::Vector{Int}                # -> row index in the compiled puzzle
    rowmask::Vector{Bits{W}}        # compiled row index -> its mask
    full::Bits{W}                   # bits outside the target are set
    lo::Vector{Int}
    hi::Vector{Int}
    vol::Vector{Int}
    exact::Bool                     # exact counts whose volume is the target's, so always feasible
    minvol::Int                     # smallest piece volume
    nbrmask::Vector{Bits{W}}        # cell position -> its adjacent cells
    boundary::Vector{Vector{Int}}   # -> cells adjacent to the placement (into masks)
end

# Cell order: fill along the target's shortest axes first, with the longest
# axis most significant, e.g. a 10x6 rectangle column by column.
function cell_order(cells::Vector{NTuple{N,Int}}) where {N}
    lo, hi = bounds(cells)
    axes = sortperm(collect(hi .- lo); rev = true, alg = MergeSort)
    sortperm(cells; by = c -> c[axes])
end

function BitSearch(::Val{W}, cells::Vector{NTuple{N,Int}}, rows::Vector{Vector{Int}},
                   rowtype, lo, hi, vol) where {W,N}
    n = length(cells)
    pos = invperm(cell_order(cells))           # target cell index -> position
    index = Dict(c => pos[i] for (i, c) in enumerate(cells))
    nbrs = [Int[] for _ in 1:n]
    for (i, c) in enumerate(cells), a in neighbors(c)
        haskey(index, a) && push!(nbrs[pos[i]], index[a])
    end
    rowpos = [sort!(pos[r]) for r in rows]
    perm = sortperm(eachindex(rows); by = r -> (first(rowpos[r]), rowtype[r]))
    rowmask = [tobits(Val(W), p) for p in rowpos]
    cellblocks = [1:0 for _ in 1:n]
    blocktype = Int[]
    blockrows = UnitRange{Int}[]
    for (i, r) in enumerate(perm)
        c, t = first(rowpos[r]), rowtype[r]
        if isempty(cellblocks[c]) || blocktype[end] != t
            push!(blocktype, t)
            push!(blockrows, i:i)
            b = length(blocktype)
            cellblocks[c] = isempty(cellblocks[c]) ? (b:b) : (first(cellblocks[c]):b)
        else
            blockrows[end] = first(blockrows[end]):i
        end
    end
    full = tobits(Val(W), n+1:64W)
    exact = lo == hi && sum(lo .* vol; init = 0) == n
    minvol = minimum((vol[t] for t in eachindex(vol) if hi[t] > 0); init = typemax(Int))
    boundary = [sort!(unique!([a for q in rowpos[r] for a in nbrs[q] if !insorted(a, rowpos[r])]))
                for r in perm]
    BitSearch{W}(cellblocks, blocktype, blockrows, rowmask[perm], perm, rowmask, full,
                 lo, hi, vol, exact, minvol, [tobits(Val(W), a) for a in nbrs], boundary)
end

# Does placement i (just added to occ) leave an empty pocket next to it with
# fewer cells than the smallest piece? Only single-cell pockets are looked for,
# as anything more costs more than it saves.
@inline function walls_off(B::BitSearch, occ::Bits, i::Int)
    B.minvol <= 1 && return false
    @inbounds for q in B.boundary[i]
        isset(occ, q) && continue
        nb = B.nbrmask[q]
        map(&, occ, nb) == nb && return true
    end
    false
end

function feasible(B::BitSearch, used::Vector{Int}, remaining::Int)
    B.exact && return true
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
    @inbounds for b in B.cellblocks[c]
        t = B.blocktype[b]
        used[t] < B.hi[t] || continue
        used[t] += 1
        rem = remaining - B.vol[t]
        if feasible(B, used, rem)
            for i in B.blockrows[b]
                m = B.masks[i]
                disjoint(m, occ) || continue
                occ2 = bor(occ, m)
                walls_off(B, occ2, i) && continue
                push!(stack, B.row[i])
                go = bsearch!(f, B, occ2, used, rem, stack, maxdepth)
                pop!(stack)
                if !go
                    used[t] -= 1
                    return false
                end
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
