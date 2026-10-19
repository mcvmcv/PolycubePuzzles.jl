# A puzzle compiled for search: the placements in use, the DLX template, and
# the symmetry reducer used to filter leaves.
struct Compiled{N}
    placements::Vector{Placement{N}}
    rows::Vector{Vector{Int}}
    rowtype::Vector{Int}
    dlx::DLX
    reducer::Reducer
end

function compile(p::Puzzle{N}, symmetry::Symbol) where {N}
    pls, rows = placement_rows(p)
    foreach(sort!, rows)
    rowtype = [pl.piece for pl in pls]
    keep, red = reduce_rows(p, rows, rowtype, solution_symmetries(p, symmetry))
    pls, rows, rowtype = pls[keep], rows[keep], rowtype[keep]
    X = DLX(ncells(p.target), rows, rowtype, first.(p.counts), last.(p.counts), ncells.(p.pieces))
    Compiled{N}(pls, rows, rowtype, X, red)
end

# Partial solutions that partition the search tree, at the smallest depth
# giving at least `target` of them.
function split_work(X::DLX, target::Int)
    prefixes = Vector{Int}[]
    for depth in 1:ncells(X)
        prefixes = Vector{Int}[]
        search!(s -> (push!(prefixes, copy(s)); true), X, depth)
        (length(prefixes) >= target || all(s -> length(s) < depth, prefixes)) && break
    end
    prefixes
end

ncells(X::DLX) = X.lastprimary - 1

# Run the search, calling visit(task, prefix, rows) for every canonical
# solution; stops when visit returns false. With ntasks > 1, the search tree is
# split into prefixes processed by `ntasks` concurrent tasks, so visit may be
# called concurrently (but never concurrently with the same `task`), and
# `prefix` numbers the subtree, in sequential search order.
function run_search(visit, c::Compiled, ntasks::Int)
    feasible(c.dlx) || return true
    n = ncells(c.dlx)
    if ntasks <= 1
        canon = Canon(c.reducer, c.rows, c.rowtype, n)
        return search!(s -> !iscanonical(canon, s) || visit(1, 1, s), c.dlx)
    end
    prefixes = split_work(c.dlx, 32 * ntasks)
    next = Threads.Atomic{Int}(1)
    stop = Threads.Atomic{Bool}(false)
    @sync for task in 1:ntasks
        Threads.@spawn begin
            # `local` matters: `canon` is also assigned above, and a closure
            # assigning it would otherwise share that one variable across tasks
            local X = deepcopy(c.dlx)
            local canon = Canon(c.reducer, c.rows, c.rowtype, n)
            while !stop[]
                local k = Threads.atomic_add!(next, 1)
                k > length(prefixes) && break
                local prefix = prefixes[k]
                foreach(r -> select!(X, r), prefix)
                local go = search!(X) do s
                    !stop[] && (!iscanonical(canon, s) || visit(task, k, s))
                end
                foreach(r -> unselect!(X, r), Iterators.reverse(prefix))
                go || (stop[] = true)
            end
        end
    end
    !stop[]
end

const SEARCH_KWARGS_DOC = """
- `symmetry = :none`: with `:all`, solutions related by a symmetry of the
  target (rotation or reflection, where these map solutions to solutions) are
  counted once; with `:rotations`, only rotations are identified.
- `ntasks`: number of concurrent search tasks; start Julia with `--threads` to
  run them in parallel.
"""

"""
    foreach_solution(f, p::Puzzle; symmetry = :none, ntasks = 1)

Call `f(sol::Solution)` for every solution of `p`. If `f` returns `false` the
search stops. Returns `true` if the search ran to completion. With
`ntasks > 1`, `f` may be called concurrently from several tasks and must be
thread-safe.

$SEARCH_KWARGS_DOC
"""
function foreach_solution(f, p::Puzzle{N}; symmetry::Symbol = :none, ntasks::Int = 1) where {N}
    c = compile(p, symmetry)
    run_search((_, _, rows) -> f(Solution{N}(c.placements[rows])), c, ntasks)
end

"""
    solve(p::Puzzle; limit = typemax(Int), symmetry = :none, ntasks = Threads.nthreads())

Return up to `limit` solutions of `p` as a `Vector{Solution}`. Without a limit
the order is the same as a sequential search, whatever `ntasks` is.

$SEARCH_KWARGS_DOC
"""
function solve(p::Puzzle{N}; limit::Integer = typemax(Int), symmetry::Symbol = :none,
               ntasks::Int = Threads.nthreads()) where {N}
    limit <= 0 && return Solution{N}[]
    c = compile(p, symmetry)
    found = [Tuple{Int,Solution{N}}[] for _ in 1:max(ntasks, 1)]
    total = Threads.Atomic{Int}(0)
    run_search(c, ntasks) do task, k, rows
        push!(found[task], (k, Solution{N}(c.placements[rows])))
        Threads.atomic_add!(total, 1) + 1 < limit
    end
    sols = reduce(vcat, found)
    sort!(sols; by = first, alg = MergeSort)  # stable: keeps order within a subtree
    last.(sols[1:min(limit, length(sols))])
end

"""
    count_solutions(p::Puzzle; symmetry = :none, ntasks = Threads.nthreads())

The number of solutions of `p`, without materializing them.

$SEARCH_KWARGS_DOC
"""
function count_solutions(p::Puzzle; symmetry::Symbol = :none, ntasks::Int = Threads.nthreads())
    c = compile(p, symmetry)
    counts = zeros(Int, max(ntasks, 1))
    run_search((task, _, _) -> (counts[task] += 1; true), c, ntasks)
    sum(counts)
end
