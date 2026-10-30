# Choosing a search engine. Neither engine is best everywhere: the bitboard
# search does very little work per node but always branches on the first empty
# cell, while DLX does more work per node but branches on the most constrained
# cell, which can make its search tree far smaller (e.g. 3D puzzles of
# identical pieces). So estimate each engine's running time and use the faster.
#
# Knuth's estimator: walk from the root to a leaf choosing a random child at
# each node; the sum over the walk of the product of the branching factors so
# far is an unbiased estimate of the number of nodes in the tree. Averaging
# over many walks, and timing them, gives an estimated running time. The
# estimate is heavy-tailed (a few rare walks into big subtrees carry much of
# the weight), so a few hundred walks can be badly off: keep walking until
# PROBE_BUDGET seconds are spent, or the search looks cheaper than more probing.

const PROBE_BATCH = 300
const PROBE_BUDGET = 0.1
const MAX_PROBES = 100_000

# Estimated running time of a search, given probe(rng) -> (nodes, visited):
# one walk's node count estimate, and how many nodes it visited.
function estimate_time(probe)
    rng = Xoshiro(1)
    nodes = 0.0
    visited = 0
    probes = 0
    elapsed = 0.0
    while true
        elapsed += @elapsed for _ in 1:PROBE_BATCH
            w, v = probe(rng)
            nodes += w
            visited += v
        end
        probes += PROBE_BATCH
        est = nodes / probes * elapsed / max(visited, 1)
        (elapsed >= PROBE_BUDGET || est <= 20 * elapsed || probes >= MAX_PROBES) && return est
    end
end

function estimate_time(B::BitSearch, rowtype::Vector{Int}, n::Int)
    used = zeros(Int, length(B.lo))
    estimate_time() do rng
        occ = B.full
        fill!(used, 0)
        remaining = n
        weight = 1.0
        nodes = 0.0
        visited = 0
        while true
            nodes += weight
            visited += 1
            remaining == 0 && break
            c = first_clear(occ)
            kids = 0
            pick = picktype = 0
            for b in B.cellblocks[c]
                t = B.blocktype[b]
                used[t] < B.hi[t] || continue
                used[t] += 1
                ok = feasible(B, used, remaining - B.vol[t])
                used[t] -= 1
                ok || continue
                for i in B.blockrows[b]
                    disjoint(B.masks[i], occ) || continue
                    walls_off(B, bor(occ, B.masks[i]), i) && continue
                    kids += 1
                    # a uniformly random child
                    rand(rng, 1:kids) == 1 && (pick = i; picktype = t)
                end
            end
            kids == 0 && break
            weight *= kids
            t = picktype
            occ = bor(occ, B.masks[pick])
            used[t] += 1
            remaining -= B.vol[t]
        end
        nodes, visited
    end
end

function estimate_time(X::DLX, rowtype::Vector{Int}, n::Int)
    feasible(X) || return 0.0
    R, D, S = X.R, X.D, X.S
    chosen = Int[]
    estimate_time() do rng
        weight = 1.0
        nodes = 0.0
        visited = 0
        empty!(chosen)
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
        nodes, visited
    end
end
