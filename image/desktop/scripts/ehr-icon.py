#!/usr/bin/env python3
"""Make the EHR launcher's icon from the EHR's own logo, at image build time (owner direction, 2026-11-12).

    python3 -I ehr-icon.py <logo.svg> <icon.svg> <fill color>

The logo is not committed to this repository: the image build takes it from the pinned EHR release (for the reference
deployment, OpenEMR's menu logo from its pinned image). The logo file is drawn without a color, which the EHR sets
through its own CSS; this script gives it the color the EHR's own themes use (for OpenEMR, #2c9cd4, the blue of
its standard themes) on a transparent square icon. The shapes are unchanged.
"""
import re
import sys

src, dst, color = sys.argv[1:4]
assert re.fullmatch(r"#[0-9a-fA-F]{6}", color), "color as #rrggbb"
svg = open(src, encoding="utf-8").read()
root = re.search(r"<svg\b[^>]*>", svg)
end = svg.rfind("</svg>")
assert root and end > root.end(), "not an SVG document"
box = re.search(r'viewBox="([\d.\s-]+)"', root.group(0))
assert box, "the logo needs a viewBox"
x, y, w, h = (float(v) for v in box.group(1).split())
inner = svg[root.end():end]
size, pad = 128, 8
scale = (size - 2 * pad) / max(w, h)
open(dst, "w", encoding="utf-8").write(
    f'<svg xmlns="http://www.w3.org/2000/svg" width="{size}" height="{size}" viewBox="0 0 {size} {size}">\n'
    f'  <g transform="translate({pad + (size - 2 * pad - w * scale) / 2:.3f},{pad + (size - 2 * pad - h * scale) / 2:.3f}) '
    f'scale({scale:.5f}) translate({-x},{-y})" fill="{color}">{inner}</g>\n</svg>\n')
