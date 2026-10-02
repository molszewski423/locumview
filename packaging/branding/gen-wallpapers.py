#!/usr/bin/env python3
"""Generate LocumView wallpaper options (light + dark) as SVG, 1920x1080 viewBox rendered at 4K."""
import math, pathlib
OUT = pathlib.Path(__file__).parent / "wallpapers"
P = {
  "dark":  dict(bg0="#090D14", bg1="#0E141C", t0="#3AA69B", t1="#1E7F75", glow="#1F6F6A", line="#7B8A99", text="#8A949E", fill="#16343A"),
  "light": dict(bg0="#E9EEF3", bg1="#F6F8FA", t0="#1E8F84", t1="#14756C", glow="#5FC4B8", line="#5B6B7A", text="#5B6672", fill="#D6EFEC"),
}
def head(c, glow_xy=(960,540), glow_r=700, glow_op=0.3):
    gx, gy = glow_xy
    return f'''<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1920 1080" width="3840" height="2160">
  <defs>
    <radialGradient id="bg" cx="0.5" cy="0.5" r="0.75"><stop offset="0" stop-color="{c['bg1']}"/><stop offset="1" stop-color="{c['bg0']}"/></radialGradient>
    <radialGradient id="glow" cx="{gx}" cy="{gy}" r="{glow_r}" gradientUnits="userSpaceOnUse"><stop offset="0" stop-color="{c['glow']}" stop-opacity="{glow_op}"/><stop offset="1" stop-color="{c['glow']}" stop-opacity="0"/></radialGradient>
    <linearGradient id="L" x1="0" y1="0" x2="1" y2="1"><stop offset="0" stop-color="{c['t0']}"/><stop offset="1" stop-color="{c['t1']}"/></linearGradient>
  </defs>
  <rect width="1920" height="1080" fill="url(#bg)"/>
  <rect width="1920" height="1080" fill="url(#glow)"/>
'''
def wordmark(c):
    return f'''  <g transform="translate(70 970)">
    <rect x="1.5" y="1.5" width="31" height="31" rx="7" fill="none" stroke="{c['text']}" stroke-width="2.2"/>
    <path d="M12 8 V24 H24" fill="none" stroke="{c['t0']}" stroke-width="2.6" stroke-linecap="round" stroke-linejoin="round"/>
  </g>
  <text x="116" y="996" font-family="Red Hat Text, Cantarell, sans-serif" font-size="25" fill="{c['text']}" letter-spacing="1">LocumView</text>
'''
def mark(c, x, y, size, sw):  # L-in-rounded-square, top-left at x,y
    s = size / 64
    return f'''  <g transform="translate({x} {y}) scale({s})">
    <rect x="6" y="6" width="52" height="52" rx="13" fill="{c['fill']}" fill-opacity="0.35" stroke="{c['line']}" stroke-opacity="0.6" stroke-width="{sw/s*0.6}"/>
    <path d="M24 18 V45 H43" fill="none" stroke="url(#L)" stroke-width="{sw/s}" stroke-linecap="round" stroke-linejoin="round"/>
  </g>
'''
def viewfinder(m, c):
    out = head(c, glow_op=0.28)
    # faint grid fading out from centre
    out += '  <defs><pattern id="grid" width="60" height="60" patternUnits="userSpaceOnUse"><path d="M60 0 H0 V60" fill="none" stroke="%s" stroke-width="1"/></pattern>' % c['line']
    out += '<radialGradient id="fade" cx="0.5" cy="0.5" r="0.55"><stop offset="0" stop-color="#fff" stop-opacity="0.18"/><stop offset="1" stop-color="#fff" stop-opacity="0"/></radialGradient><mask id="gm"><rect width="1920" height="1080" fill="url(#fade)"/></mask></defs>\n'
    out += '  <rect width="1920" height="1080" fill="url(#grid)" mask="url(#gm)"/>\n'
    x0, y0, x1, y1, a, r = 640, 260, 1280, 820, 90, 28
    out += f'''  <g fill="none" stroke="url(#L)" stroke-width="7" stroke-linecap="round" stroke-linejoin="round">
    <path d="M{x0} {y0+a} V{y0+r} Q{x0} {y0} {x0+r} {y0} H{x0+a}"/>
    <path d="M{x1-a} {y0} H{x1-r} Q{x1} {y0} {x1} {y0+r} V{y0+a}"/>
    <path d="M{x1} {y1-a} V{y1-r} Q{x1} {y1} {x1-r} {y1} H{x1-a}"/>
    <path d="M{x0+a} {y1} H{x0+r} Q{x0} {y1} {x0} {y1-r} V{y1-a}"/>
  </g>
'''
    out += mark(c, 900, 480, 120, 9)
    return out + wordmark(c) + "</svg>\n"
def pulse(m, c):
    out = head(c, glow_xy=(1180, 600), glow_r=650, glow_op=0.3)
    y = 600
    pts = [(-20, y), (1000, y), (1030, y-18), (1060, y), (1090, y), (1110, y+40), (1140, y-210), (1170, y+70), (1195, y), (1250, y), (1290, y-30), (1340, y), (1440, y)]
    d = "M" + " L".join(f"{px} {py}" for px, py in pts)
    out += f'''  <defs><linearGradient id="fadeL" x1="0" x2="1"><stop offset="0" stop-color="{c['t0']}" stop-opacity="0"/><stop offset="0.45" stop-color="{c['t0']}" stop-opacity="0.9"/><stop offset="1" stop-color="{c['t1']}"/></linearGradient>
  <filter id="soft" x="-5%" y="-50%" width="110%" height="200%"><feGaussianBlur stdDeviation="9"/></filter></defs>
  <path d="{d}" fill="none" stroke="{c['t0']}" stroke-width="14" stroke-linejoin="round" opacity="0.25" filter="url(#soft)"/>
  <path d="{d}" fill="none" stroke="url(#fadeL)" stroke-width="5" stroke-linejoin="round" stroke-linecap="round"/>
'''
    # the trace runs into the corner of an L (solid stroke: gradients on zero-width lines render nothing)
    out += f'  <path d="M1440 {y-200} V{y} H1580" fill="none" stroke="{c['t0']}" stroke-width="7" stroke-linecap="round" stroke-linejoin="round"/>\n'
    return out + wordmark(c) + "</svg>\n"
def horizon(m, c):
    out = head(c, glow_xy=(960, 640), glow_r=900, glow_op=0.32)
    hy = 640
    out += f'  <defs><linearGradient id="floor" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#fff" stop-opacity="0"/><stop offset="1" stop-color="#fff" stop-opacity="0.5"/></linearGradient><mask id="fm"><rect y="{hy}" width="1920" height="{1080-hy}" fill="url(#floor)"/></mask></defs>\n'
    lines = []
    for i in range(-24, 25):
        lines.append(f'<line x1="{960 + i*14}" y1="{hy}" x2="{960 + i*170}" y2="1080"/>')
    for k in range(1, 12):
        yy = hy + (1080 - hy) * (k / 11) ** 2.2
        lines.append(f'<line x1="0" y1="{yy:.1f}" x2="1920" y2="{yy:.1f}"/>')
    out += f'  <g stroke="{c["t0"]}" stroke-width="1.5" mask="url(#fm)">' + "".join(lines) + "</g>\n"
    out += f'  <line x1="0" y1="{hy}" x2="1920" y2="{hy}" stroke="{c["t0"]}" stroke-width="2" opacity="0.6"/>\n'
    out += mark(c, 900, 380, 120, 9)
    return out + wordmark(c) + "</svg>\n"
def monogram(m, c):
    out = head(c, glow_xy=(1500, 900), glow_r=900, glow_op=0.25)
    out += f'''  <rect x="1180" y="180" width="1100" height="1100" rx="240" fill="{c['fill']}" fill-opacity="0.18" stroke="{c['line']}" stroke-opacity="0.25" stroke-width="3"/>
  <path d="M1500 420 V900 H1980" fill="none" stroke="url(#L)" stroke-width="64" stroke-linecap="round" stroke-linejoin="round" opacity="0.55"/>
'''
    return out + wordmark(c) + "</svg>\n"
for name, fn in dict(viewfinder=viewfinder, pulse=pulse, horizon=horizon, monogram=monogram).items():
    for mode, c in P.items():
        (OUT / f"{name}-{mode}.svg").write_text(fn(mode, c))
print("generated", sorted(p.name for p in OUT.glob("*.svg")))
