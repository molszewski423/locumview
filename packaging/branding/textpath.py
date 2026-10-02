"""Render text to SVG path data with a TTF (fontTools), so wallpapers need no installed fonts."""
from functools import lru_cache
from fontTools.ttLib import TTFont
from fontTools.pens.svgPathPen import SVGPathPen
from fontTools.pens.transformPen import TransformPen

FONT_DIR = "/home/mike/.local/share/fonts/JetBrainsMonoNerd"

@lru_cache(None)
def font(weight="Medium"):
    return TTFont(f"{FONT_DIR}/JetBrainsMonoNerdFont-{weight}.ttf")

def text_path(text, x, y, size, weight="Medium", tracking=0.0):
    """Path 'd' for text with its baseline at (x, y). tracking is extra advance in px."""
    f = font(weight)
    gs, cmap, upm = f.getGlyphSet(), f.getBestCmap(), f["head"].unitsPerEm
    s = size / upm
    pen = SVGPathPen(gs)
    cx = x
    for ch in text:
        g = cmap.get(ord(ch))
        if g is None:
            continue
        gs[g].draw(TransformPen(pen, (s, 0, 0, -s, cx, y)))
        cx += gs[g].width * s + tracking
    return pen.getCommands(), cx - x

def width(text, size, weight="Medium", tracking=0.0):
    return text_path(text, 0, 0, size, weight, tracking)[1]
