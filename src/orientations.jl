# Orientations in N dimensions are the signed permutation matrices (the
# hyperoctahedral group, of order N! * 2^N). Those with determinant +1 are the
# proper rotations; the rest include a reflection.

function permutations_of(n::Int)
    n == 0 && return [Int[]]
    out = Vector{Int}[]
    for p in permutations_of(n - 1), k in 0:n-1
        q = copy(p)
        insert!(q, n - k, n)
        push!(out, q)
    end
    out
end

function parity(p::AbstractVector{Int})
    s = 1
    for i in eachindex(p), j in i+1:lastindex(p)
        p[i] > p[j] && (s = -s)
    end
    s
end

"""
    symmetries(N; reflections::Bool)

All signed permutations of N axes as `(perm, signs)` pairs, where the image of
cell `c` is `ntuple(i -> signs[i] * c[perm[i]], N)`. With `reflections = false`
only proper rotations (determinant +1) are returned.
"""
function symmetries(N::Int; reflections::Bool)
    out = Tuple{Vector{Int},Vector{Int}}[]
    for p in permutations_of(N), m in 0:(1 << N)-1
        signs = [((m >> (i - 1)) & 1) == 1 ? -1 : 1 for i in 1:N]
        det = parity(p) * prod(signs; init = 1)
        (reflections || det == 1) && push!(out, (p, signs))
    end
    out
end

transform(c::NTuple{N,Int}, perm, signs) where {N} = ntuple(i -> signs[i] * c[perm[i]], N)

"""
    orientations(s::Shape; reflections::Bool)

The distinct orientations of `s`, each normalized (see [`normalize`](@ref)).
With `reflections = true` mirror images are included.
"""
function orientations(s::Shape{N}; reflections::Bool) where {N}
    out = Set{Shape{N}}()
    for (perm, signs) in symmetries(N; reflections)
        push!(out, normalize(Shape{N}([transform(c, perm, signs) for c in s.cells])))
    end
    sort!(collect(out))
end
