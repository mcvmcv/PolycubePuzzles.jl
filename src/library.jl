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
