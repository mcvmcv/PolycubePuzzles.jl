# Dancing links (Knuth, Algorithm X) with piece-type multiplicities.
#
# Primary columns are the target cells and must each be covered exactly once.
# Every piece type also has a secondary column holding all of its placements.
# Choosing a placement increments its type's count; when the count reaches the
# type's maximum the type column is covered, which hides the remaining
# placements of that type. Branching is only ever on cell columns, so copies of
# the same piece are never distinguished.
#
# Node 1 is the root, nodes 2:ncols+1 are column headers (column k is node
# k + 1), and the remaining nodes belong to rows.

mutable struct DLX
    L::Vector{Int}
    R::Vector{Int}
    U::Vector{Int}
    D::Vector{Int}
    C::Vector{Int}          # node -> its column header
    S::Vector{Int}          # header -> number of rows in the column
    row::Vector{Int}        # node -> row index
    rowfirst::Vector{Int}   # row -> its first node
    lastprimary::Int        # header nodes 2:lastprimary are primary
    rowtype::Vector{Int}    # row -> piece type
    typecol::Vector{Int}    # piece type -> header node
    lo::Vector{Int}
    hi::Vector{Int}
    vol::Vector{Int}        # piece type -> number of cells
    used::Vector{Int}       # piece type -> copies currently placed
    remaining::Int          # uncovered cells
    stack::Vector{Int}      # chosen rows
end

function DLX(ncells::Int, rows::Vector{Vector{Int}}, rowtype::Vector{Int},
             lo::Vector{Int}, hi::Vector{Int}, vol::Vector{Int})
    ntypes = length(lo)
    ncols = ncells + ntypes
    n = 1 + ncols + sum(length, rows; init = 0) + length(rows)
    L = zeros(Int, n); R = zeros(Int, n); U = zeros(Int, n); D = zeros(Int, n)
    C = zeros(Int, n); S = zeros(Int, n); row = zeros(Int, n)
    rowfirst = zeros(Int, length(rows))
    lastprimary = ncells + 1
    # root and primary headers form a circular list; secondary headers are self-linked
    for h in 1:lastprimary
        L[h] = h == 1 ? lastprimary : h - 1
        R[h] = h == lastprimary ? 1 : h + 1
    end
    for h in lastprimary+1:ncols+1
        L[h] = R[h] = h
    end
    for h in 2:ncols+1
        U[h] = D[h] = C[h] = h
    end
    node = ncols + 1
    for (r, cells) in enumerate(rows)
        first = node + 1
        rowfirst[r] = first
        for col in Iterators.flatten((cells, ncells + rowtype[r]))
            node += 1
            h = col + 1
            C[node] = h; row[node] = r; S[h] += 1
            U[node] = U[h]; D[node] = h; D[U[h]] = node; U[h] = node
            if node > first
                L[node] = node - 1; R[node-1] = node
            end
        end
        L[first] = node; R[node] = first
    end
    typecol = [lastprimary + t for t in 1:ntypes]
    DLX(L, R, U, D, C, S, row, rowfirst, lastprimary, rowtype, typecol, lo, hi, vol,
        zeros(Int, ntypes), ncells, Int[])
end

function cover!(X::DLX, c::Int)
    L, R, U, D, C, S = X.L, X.R, X.U, X.D, X.C, X.S
    @inbounds begin
        R[L[c]] = R[c]; L[R[c]] = L[c]
        i = D[c]
        while i != c
            j = R[i]
            while j != i
                D[U[j]] = D[j]; U[D[j]] = U[j]; S[C[j]] -= 1
                j = R[j]
            end
            i = D[i]
        end
    end
    nothing
end

function uncover!(X::DLX, c::Int)
    L, R, U, D, C, S = X.L, X.R, X.U, X.D, X.C, X.S
    @inbounds begin
        i = U[c]
        while i != c
            j = L[i]
            while j != i
                S[C[j]] += 1; D[U[j]] = j; U[D[j]] = j
                j = L[j]
            end
            i = U[i]
        end
        R[L[c]] = c; L[R[c]] = c
    end
    nothing
end

# Can the remaining cells still be filled within the count bounds?
function feasible(X::DLX)
    need = 0
    cap = 0
    @inbounds for t in eachindex(X.lo)
        need += max(0, X.lo[t] - X.used[t]) * X.vol[t]
        cap += min(X.hi[t] - X.used[t], X.remaining) * X.vol[t]
    end
    need <= X.remaining <= cap
end

# Add row r to the partial solution (as if chosen by the search).
function select!(X::DLX, r::Int)
    R, C = X.R, X.C
    first = X.rowfirst[r]
    j = first
    while true
        C[j] <= X.lastprimary && cover!(X, C[j])
        j = R[j]
        j == first && break
    end
    t = X.rowtype[r]
    X.used[t] += 1
    X.remaining -= X.vol[t]
    X.used[t] == X.hi[t] && cover!(X, X.typecol[t])
    push!(X.stack, r)
    nothing
end

# Undo select!(X, r); must be called in reverse order of selection.
function unselect!(X::DLX, r::Int)
    L, C = X.L, X.C
    pop!(X.stack)
    t = X.rowtype[r]
    X.used[t] == X.hi[t] && uncover!(X, X.typecol[t])
    X.remaining += X.vol[t]
    X.used[t] -= 1
    first = X.rowfirst[r]
    j = L[first]
    while true
        C[j] <= X.lastprimary && uncover!(X, C[j])
        j == first && break
        j = L[j]
    end
    nothing
end

# Calls f(X.stack) for each solution, or for each partial solution with
# `maxdepth` rows; stops early if f returns false. Returns false if stopped early.
function search!(f, X::DLX, maxdepth::Int = typemax(Int))
    L, R, D, C, S = X.L, X.R, X.D, X.C, X.S
    if R[1] == 1 || length(X.stack) >= maxdepth
        return f(X.stack) !== false
    end
    # choose the cell with fewest candidate placements
    c = R[1]
    best = S[c]
    j = R[c]
    @inbounds while j != 1 && best > 1
        if S[j] < best
            c = j; best = S[j]
        end
        j = R[j]
    end
    best == 0 && return true
    cover!(X, c)
    r = D[c]
    @inbounds while r != c
        t = X.rowtype[X.row[r]]
        j = R[r]
        while j != r
            C[j] <= X.lastprimary && cover!(X, C[j])
            j = R[j]
        end
        X.used[t] += 1
        X.remaining -= X.vol[t]
        full = X.used[t] == X.hi[t]
        full && cover!(X, X.typecol[t])
        push!(X.stack, X.row[r])
        go = feasible(X) ? search!(f, X, maxdepth) : true
        pop!(X.stack)
        full && uncover!(X, X.typecol[t])
        X.remaining += X.vol[t]
        X.used[t] -= 1
        j = L[r]
        while j != r
            C[j] <= X.lastprimary && uncover!(X, C[j])
            j = L[j]
        end
        if !go
            uncover!(X, c)
            return false
        end
        r = D[r]
    end
    uncover!(X, c)
    true
end
