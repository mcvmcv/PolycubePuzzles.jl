# A puzzle compiled for search: the placements in use, the bitboard search,
# and the symmetry reducer used to filter leaves.
struct Compiled{N,S}
    placements::Vector{Placement{N}}
    rows::Vector{Vector{Int}}
    rowtype::Vector{Int}
    search::S
    reducer::Reducer
    ncells::Int
end

function compile(p::Puzzle{N}, symmetry::Symbol; engine::Symbol = :auto) where {N}
    engine in (:auto, :dlx, :bitboard) ||
        throw(ArgumentError("engine must be :auto, :dlx or :bitboard, got :$engine"))
    pls, rows = placement_rows(p)
    foreach(sort!, rows)
    rowtype = [pl.piece for pl in pls]
    keep, red = reduce_rows(p, rows, rowtype, solution_symmetries(p, symmetry))
    pls, rows, rowtype = pls[keep], rows[keep], rowtype[keep]
    n = ncells(p.target)
    lo, hi, vol = first.(p.counts), last.(p.counts), ncells.(p.pieces)
    build_dlx() = DLX(n, rows, rowtype, lo, hi, vol)
    build_bits() = BitSearch(Val(max(1, cld(n, 64))), p.target.cells, rows, rowtype, lo, hi, vol)
    S = if engine === :dlx
        build_dlx()
    elseif engine === :bitboard
        build_bits()
    else
        # whichever engine's search is estimated to take less time
        X, B = build_dlx(), build_bits()
        estimate_time(X, rowtype, n) <= estimate_time(B, rowtype, n) ? X : B
    end
    Compiled(pls, rows, rowtype, S, red, n)
end

# Search the subtree below the partial solution `prefix` (row indices).
start!(f, c::Compiled{N,<:BitSearch}, prefix, maxdepth = typemax(Int)) where {N} =
    bsearch_from!(f, c.search, c.rowtype, c.ncells, prefix, maxdepth)
start!(f, c::Compiled{N,DLX}, prefix, maxdepth = typemax(Int)) where {N} =
    dlx_from!(f, c.search, prefix, maxdepth)

# A copy of the compiled puzzle that a concurrent task can search on its own.
private(c::Compiled{N,DLX}) where {N} =
    Compiled(c.placements, c.rows, c.rowtype, deepcopy(c.search), c.reducer, c.ncells)
private(c::Compiled) = c

# Partial solutions that partition the search tree, at the smallest depth
# giving at least `target` of them.
function split_work(c::Compiled, target::Int)
    prefixes = Vector{Int}[]
    for depth in 1:c.ncells
        prefixes = Vector{Int}[]
        start!(s -> (push!(prefixes, copy(s)); true), c, Int[], depth)
        (length(prefixes) >= target || all(s -> length(s) < depth, prefixes)) && break
    end
    prefixes
end

# Run the search, calling visit(task, prefix, rows) for every canonical
# solution; stops when visit returns false. With ntasks > 1, the search tree is
# split into prefixes processed by `ntasks` concurrent tasks, so visit may be
# called concurrently (but never concurrently with the same `task`), and
# `prefix` numbers the subtree, in sequential search order.
function run_search(visit, c::Compiled, ntasks::Int)
    if ntasks <= 1
        canon = Canon(c.reducer, c.rows, c.rowtype, c.ncells)
        return start!(s -> !iscanonical(canon, s) || visit(1, 1, s), c, Int[])
    end
    prefixes = split_work(c, 32 * ntasks)
    next = Threads.Atomic{Int}(1)
    stop = Threads.Atomic{Bool}(false)
    @sync for task in 1:ntasks
        Threads.@spawn begin
            # `local` matters: `canon` is also assigned above, and a closure
            # assigning it would otherwise share that one variable across tasks
            local canon = Canon(c.reducer, c.rows, c.rowtype, c.ncells)
            local mine = private(c)
            while !stop[]
                local k = Threads.atomic_add!(next, 1)
                k > length(prefixes) && break
                local go = start!(mine, prefixes[k]) do s
                    !stop[] && (!iscanonical(canon, s) || visit(task, k, s))
                end
                go || (stop[] = true)
            end
        end
    end
    !stop[]
end

# With `swaps`, the record of classes seen; otherwise nothing.
classes(p::Puzzle, c::Compiled, swaps::Bool) = swaps ? Classes(Swapper(p, c.reducer.syms)) : nothing

# A found solution's class code, for the classes record `cl`.
class_of(cl::Classes, c::Compiled, rows) = class_code(cl, [(c.rowtype[r], c.rows[r]) for r in rows])

const SEARCH_KWARGS_DOC = """
- `symmetry = :none`: with `:all`, solutions related by a symmetry of the
  target (rotation or reflection, where these map solutions to solutions) are
  counted once; with `:rotations`, only rotations are identified.
- `swaps = false`: if `true`, solutions that differ only by two touching
  pieces trading places (their cells together filled by the same two pieces
  another way) are counted once, as are chains of such swaps. Combined with
  `symmetry`, one solution is kept per class of solutions related by swaps and
  symmetries. Classes are found by enumerating solutions, so this counts no
  faster than finding them all.
- `ntasks`: number of concurrent search tasks; start Julia with `--threads` to
  run them in parallel.
- `engine = :auto`: the search algorithm. `:bitboard` fills the first empty
  cell each time, with very cheap steps; `:dlx` (dancing links) fills the most
  constrained cell, which can make the search far smaller. `:auto` estimates
  both from a few hundred random probes of the search tree and uses the faster.
"""

"""
    foreach_solution(f, p::Puzzle; symmetry = :none, swaps = false, ntasks = 1)

Call `f(sol::Solution)` for every solution of `p`. If `f` returns `false` the
search stops. Returns `true` if the search ran to completion. With
`ntasks > 1`, `f` may be called concurrently from several tasks and must be
thread-safe, and with `swaps` which solution stands for a class can vary.

$SEARCH_KWARGS_DOC
"""
function foreach_solution(f, p::Puzzle{N}; symmetry::Symbol = :none, swaps::Bool = false,
                          ntasks::Int = 1, engine::Symbol = :auto) where {N}
    c = compile(p, symmetry; engine)
    cl = classes(p, c, swaps)
    run_search(c, ntasks) do _, _, rows
        cl === nothing || isnew!(cl, class_of(cl, c, rows)) || return true
        f(Solution{N}(c.placements[rows]))
    end
end

"""
    solve(p::Puzzle; limit = typemax(Int), symmetry = :none, swaps = false,
          ntasks = Threads.nthreads())

Return up to `limit` solutions of `p` as a `Vector{Solution}`. Without a limit
the order is the same as a sequential search, whatever `ntasks` is.

$SEARCH_KWARGS_DOC
"""
function solve(p::Puzzle{N}; limit::Integer = typemax(Int), symmetry::Symbol = :none,
               swaps::Bool = false, ntasks::Int = Threads.nthreads(),
               engine::Symbol = :auto) where {N}
    limit <= 0 && return Solution{N}[]
    c = compile(p, symmetry; engine)
    cl = classes(p, c, swaps)
    found = [Tuple{Int,Solution{N},Vector{Int}}[] for _ in 1:max(ntasks, 1)]
    total = Threads.Atomic{Int}(0)
    run_search(c, ntasks) do task, k, rows
        code = cl === nothing ? Int[] : class_of(cl, c, rows)
        push!(found[task], (k, Solution{N}(c.placements[rows]), code))
        cl === nothing || isnew!(cl, code) || return true
        Threads.atomic_add!(total, 1) + 1 < limit
    end
    sols = reduce(vcat, found)
    sort!(sols; by = first, alg = MergeSort)  # stable: keeps order within a subtree
    # with swaps, the first solution of each class in search order stands for it
    cl === nothing || unique!(last, sols)
    [sol for (_, sol, _) in sols[1:min(limit, length(sols))]]
end

"""
    count_solutions(p::Puzzle; symmetry = :none, swaps = false, ntasks = Threads.nthreads())

The number of solutions of `p`, without materializing them.

$SEARCH_KWARGS_DOC
"""
function count_solutions(p::Puzzle; symmetry::Symbol = :none, swaps::Bool = false,
                         ntasks::Int = Threads.nthreads(), engine::Symbol = :auto)
    c = compile(p, symmetry; engine)
    cl = classes(p, c, swaps)
    counts = zeros(Int, max(ntasks, 1))
    run_search(c, ntasks) do task, _, rows
        (cl === nothing || isnew!(cl, class_of(cl, c, rows))) && (counts[task] += 1)
        true
    end
    sum(counts)
end
