#!/usr/bin/env python3
"""GDM / lock-screen logo: white L mark + 'LocumView' in JetBrains Mono Nerd Font (outlined). 180x48 logical."""
import sys, pathlib
sys.path.insert(0, str(pathlib.Path(__file__).parent))
from textpath import text_path
d, w = text_path("LocumView", 46, 32, 20, "Medium", tracking=0.3)
W = round(46 + w + 4)
svg = f'''<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {W} 48" width="{W}" height="48">
  <rect x="3" y="9" width="30" height="30" rx="7" fill="none" stroke="#FFFFFF" stroke-width="2.4"/>
  <path d="M13.5 15 V31 H25.5" fill="none" stroke="#5EEAD4" stroke-width="2.8" stroke-linecap="round" stroke-linejoin="round"/>
  <path d="{d}" fill="#FFFFFF"/>
</svg>
'''
(pathlib.Path(__file__).parent / "locumview-gdm-logo.svg").write_text(svg)
print(W)
