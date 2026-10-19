const PENTOMINO_ART = (
    F = ".XX\nXX.\n.X.",
    I = "XXXXX",
    L = "XXXX\nX...",
    N = "XX..\n.XXX",
    P = "XX\nXX\nX.",
    T = "XXX\n.X.\n.X.",
    U = "X.X\nXXX",
    V = "X..\nX..\nXXX",
    W = "X..\nXX.\n.XX",
    X = ".X.\nXXX\n.X.",
    Y = "XXXX\n.X..",
    Z = "XX.\n.X.\n.XX",
)

"""
    pentominoes()

The twelve pentominoes as a `NamedTuple` of 2D shapes, keyed by their
conventional letters `F I L N P T U V W X Y Z`.
"""
pentominoes() = map(parse_shape, PENTOMINO_ART)

"""
    soma()

The seven Soma cube pieces as a `NamedTuple` of 3D shapes `V L T Z A B P`.
`A` and `B` are the mirror-image screw pieces and `P` is the tripod.
"""
soma() = (
    V = Shape((1, 1, 1), (2, 1, 1), (1, 2, 1)),
    L = Shape((1, 1, 1), (2, 1, 1), (3, 1, 1), (1, 2, 1)),
    T = Shape((1, 1, 1), (2, 1, 1), (3, 1, 1), (2, 2, 1)),
    Z = Shape((1, 1, 1), (2, 1, 1), (2, 2, 1), (3, 2, 1)),
    A = Shape((1, 1, 1), (2, 1, 1), (1, 2, 1), (2, 1, 2)),
    B = Shape((1, 1, 1), (2, 1, 1), (1, 2, 1), (1, 2, 2)),
    P = Shape((1, 1, 1), (2, 1, 1), (1, 2, 1), (1, 1, 2)),
)
