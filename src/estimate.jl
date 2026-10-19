# Choosing a search engine. Neither engine is best everywhere: the bitboard
# search does very little work per node but always branches on the first empty
# cell, while DLX does more work per node but branches on the most constrained
# cell, which can make its search tree far smaller (e.g. 3D puzzles of
# identical pieces). So estimate each engine's running time and use the faster.
#
# Knuth's estimator: walk from the root to a leaf choosing a random child at
# each node; the sum over the walk of the product of the branching factors so
# far is an unbiased estimate of the number of nodes in the tree. Averaging
# over many walks, and timing them, gives an estimated running time.

const PROBES = 300

function estimate_time(B::BitSearch, rowtype::Vector{Int}, n::Int)
    rng = Xoshiro(1)
    nodes = 0.0
    visited = 0
    used = zeros(Int, length(B.lo))
    elapsed = @elapsed for _ in 1:PROBES
        occ = B.full
        fill!(used, 0)
        remaining = n
        weight = 1.0
        while true
            nodes += weight
            visited += 1
            remaining == 0 && break
            c = first_clear(occ)
            kids = 0
            pick = 0
            for i in B.starts[c]
                m = B.masks[i]
                disjoint(m, occ) || continue
                t = B.rowtype[i]
                used[t] < B.hi[t] || continue
                used[t] += 1
                ok = feasible(B, used, remaining - B.vol[t])
                used[t] -= 1
                ok || continue
                kids += 1
                rand(rng, 1:kids) == 1 && (pick = i)   # a uniformly random child
            end
            kids == 0 && break
            weight *= kids
            t = B.rowtype[pick]
            occ = bor(occ, B.masks[pick])
            used[t] += 1
            remaining -= B.vol[t]
        end
    end
    nodes / PROBES * elapsed / visited
end

function estimate_time(X::DLX, rowtype::Vector{Int}, n::Int)
    rng = Xoshiro(1)
    nodes = 0.0
    visited = 0
    R, D, S = X.R, X.D, X.S
    chosen = Int[]
    elapsed = @elapsed for _ in 1:PROBES
        weight = 1.0
        empty!(chosen)
        feasible(X) || break
        while true
            nodes += weight
            visited += 1
            R[1] == 1 && break
            # the column the search would branch on
            c = R[1]
            best = S[c]
            j = R[c]
            while j != 1 && best > 1
                if S[j] < best
                    c = j
                    best = S[j]
                end
                j = R[j]
            end
            best == 0 && break
            weight *= best
            r = D[c]
            for _ in 2:rand(rng, 1:best)
                r = D[r]
            end
            row = X.row[r]
            select!(X, row)
            push!(chosen, row)
            feasible(X) || break
        end
        foreach(r -> unselect!(X, r), Iterators.reverse(chosen))
    end
    nodes / PROBES * elapsed / visited
end
