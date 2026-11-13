#!/usr/bin/env python3
"""Make the EHR launcher's icon from the EHR's own logo, at image build time (owner direction, 2026-11-12).

    python3 -I ehr-icon.py <logo.svg> <icon.svg>

The logo is not committed to this repository: the image build takes it from the pinned EHR release (for the reference
deployment, OpenEMR's menu logo from its pinned image) and places it, unchanged, on a white rounded tile so that a
logo drawn in black, which the EHR colors through its own CSS, stays visible on the dark dock.
"""
import re
import sys

src, dst = sys.argv[1:3]
svg = open(src, encoding="utf-8").read()
root = re.search(r"<svg\b[^>]*>", svg)
end = svg.rfind("</svg>")
assert root and end > root.end(), "not an SVG document"
box = re.search(r'viewBox="([\d.\s-]+)"', root.group(0))
assert box, "the logo needs a viewBox"
x, y, w, h = (float(v) for v in box.group(1).split())
inner = svg[root.end():end]
size, pad = 128, 16
scale = (size - 2 * pad) / max(w, h)
open(dst, "w", encoding="utf-8").write(
    f'<svg xmlns="http://www.w3.org/2000/svg" width="{size}" height="{size}" viewBox="0 0 {size} {size}">\n'
    f'  <rect width="{size}" height="{size}" rx="28" fill="#ffffff"/>\n'
    f'  <g transform="translate({pad + (size - 2 * pad - w * scale) / 2:.3f},{pad + (size - 2 * pad - h * scale) / 2:.3f}) '
    f'scale({scale:.5f}) translate({-x},{-y})" fill="#000000">{inner}</g>\n</svg>\n')
