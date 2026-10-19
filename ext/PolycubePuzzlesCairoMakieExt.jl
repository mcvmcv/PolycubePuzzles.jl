module PolycubePuzzlesCairoMakieExt

# Multi-page PDFs, which Makie's `save` can't write: draw each figure onto one
# Cairo PDF surface, starting a new page after each.

using PolycubePuzzles
using CairoMakie
using CairoMakie: Cairo, Makie

function PolycubePuzzles.save_pages(path::AbstractString, figs::AbstractVector)
    isempty(figs) && throw(ArgumentError("no pages to save"))
    w, h = size(first(figs).scene)
    # one unit is one PDF point, so a figure of size (595, 842) is an A4 page
    config = CairoMakie.ScreenConfig(1.0, 1.0, :best, false, false, nothing)
    surface = Cairo.CairoPDFSurface(path, w, h)
    for fig in figs
        Makie.update_state_before_display!(fig)
        screen = CairoMakie.Screen(fig.scene, config, surface)
        CairoMakie.cairo_draw(screen, fig.scene)
        Cairo.show_page(screen.context)
    end
    Cairo.finish(surface)
    path
end

end
