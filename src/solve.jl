function build(p::Puzzle)
    pls, rows = placement_rows(p)
    rowtype = [pl.piece for pl in pls]
    lo = first.(p.counts)
    hi = last.(p.counts)
    vol = ncells.(p.pieces)
    pls, DLX(ncells(p.target), rows, rowtype, lo, hi, vol)
end

"""
    foreach_solution(f, p::Puzzle)

Call `f(sol::Solution)` for every solution of `p`. If `f` returns `false` the
search stops. Returns `true` if the search ran to completion.
"""
function foreach_solution(f, p::Puzzle{N}) where {N}
    pls, X = build(p)
    feasible(X) || return true
    search!(rows -> f(Solution{N}(pls[rows])), X)
end

"""
    solve(p::Puzzle; limit = typemax(Int))

Return up to `limit` solutions of `p` as a `Vector{Solution}`.
"""
function solve(p::Puzzle{N}; limit::Integer = typemax(Int)) where {N}
    out = Solution{N}[]
    limit <= 0 && return out
    foreach_solution(p) do sol
        push!(out, sol)
        length(out) < limit
    end
    out
end

"""
    count_solutions(p::Puzzle)

The number of solutions of `p`, without materializing them. Solutions related
by a symmetry of the target are counted separately.
"""
function count_solutions(p::Puzzle)
    _, X = build(p)
    feasible(X) || return 0
    n = Ref(0)
    search!(_ -> (n[] += 1; true), X)
    n[]
end
