#!/usr/bin/env python3
"""Replace the bottom-left <text>LocumView</text> in every wallpaper SVG with JetBrains Mono Nerd Font outlines."""
import re, pathlib, sys
sys.path.insert(0, str(pathlib.Path(__file__).parent))
from textpath import text_path
pat = re.compile(r'<text x="116" y="996"[^>]*fill="(#[0-9A-Fa-f]{6})"[^>]*>LocumView</text>')
for f in sorted((pathlib.Path(__file__).parent / "wallpapers").glob("*.svg")):
    s = f.read_text()
    m = pat.search(s)
    if not m:
        print("skip (no text wordmark)", f.name); continue
    d, _ = text_path("LocumView", 114, 995, 25, "Medium", tracking=0.5)
    s = pat.sub(f'<path d="{d}" fill="{m.group(1)}"/>', s)
    f.write_text(s); print("outlined", f.name)
