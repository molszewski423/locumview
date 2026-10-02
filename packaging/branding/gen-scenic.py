#!/usr/bin/env python3
"""LocumView scenic wallpapers (light + dark), procedurally drawn SVG. Deterministic: fixed seeds."""
import math, random, pathlib
OUT = pathlib.Path(__file__).parent / "wallpapers"
W, H = 1920, 1080

def lerp(a, b, t): return a + (b - a) * t
def hx(c): return tuple(int(c[i:i+2], 16) for i in (1, 3, 5))
def mix(c1, c2, t): return "#%02X%02X%02X" % tuple(round(lerp(a, b, t)) for a, b in zip(hx(c1), hx(c2)))

def svg(body, defs=""):
    return (f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {W} {H}" width="3840" height="2160">\n'
            f'<defs>{defs}</defs>\n{body}</svg>\n')

def vgrad(gid, stops, x2=0, y2=1):
    s = "".join(f'<stop offset="{o}" stop-color="{c}" stop-opacity="{op}"/>' for o, c, op in stops)
    return f'<linearGradient id="{gid}" x1="0" y1="0" x2="{x2}" y2="{y2}">{s}</linearGradient>'

def wordmark(text, accent):
    return f'''<g transform="translate(70 970)">
  <rect x="1.5" y="1.5" width="31" height="31" rx="7" fill="none" stroke="{text}" stroke-width="2.2"/>
  <path d="M12 8 V24 H24" fill="none" stroke="{accent}" stroke-width="2.6" stroke-linecap="round" stroke-linejoin="round"/>
</g>
<text x="116" y="996" font-family="Red Hat Text, Cantarell, sans-serif" font-size="25" fill="{text}" letter-spacing="1">LocumView</text>
'''

def stars(rng, n, ymax, color="#FFFFFF", maxr=1.6):
    out = []
    for _ in range(n):
        x, y = rng.uniform(0, W), rng.uniform(0, ymax) ** 1.0
        r = rng.choice([0.5, 0.7, 0.9, 1.1, maxr]) if rng.random() > 0.05 else maxr * 1.4
        op = rng.uniform(0.25, 0.95) * (1 - y / ymax * 0.6)
        out.append(f'<circle cx="{x:.1f}" cy="{y:.1f}" r="{r}" fill="{color}" opacity="{op:.2f}"/>')
    return "".join(out)

def ridge(rng, base, amp, rough=0.55, steps=8):
    """Midpoint-displacement ridgeline, closed down to the bottom edge."""
    pts = [base + rng.uniform(-amp, amp) * 0.5, base + rng.uniform(-amp, amp) * 0.5]
    disp = amp
    for _ in range(steps):
        nxt = []
        for a, b in zip(pts, pts[1:]):
            nxt += [a, (a + b) / 2 + rng.uniform(-disp, disp)]
        nxt.append(pts[-1]); pts = nxt; disp *= rough
    n = len(pts) - 1
    d = "M0 %d " % H + " ".join(f"L{i * W / n:.1f} {y:.1f}" for i, y in enumerate(pts)) + f" L{W} {H} Z"
    return d

# ---------------------------------------------------------------- 1. Ridgeline
def ridgeline(mode):
    rng = random.Random(7)
    if mode == "dark":
        sky = [(0, "#060A13", 1), (0.55, "#0D1E2C", 1), (0.8, "#174A4F", 1), (1, "#2B7A72", 1)]
        back, front, mist, text = "#1D4650", "#04080C", "#3AA69B", "#9AA7B1"
    else:
        sky = [(0, "#BFD9E6", 1), (0.5, "#E9EEF0", 1), (0.78, "#F7E3D3", 1), (1, "#F6C9A8", 1)]
        back, front, mist, text = "#B4CCD4", "#24434D", "#FFFFFF", "#DCE6EA"
    defs = vgrad("sky", sky) + '<filter id="blur"><feGaussianBlur stdDeviation="22"/></filter>'
    body = '<rect width="1920" height="1080" fill="url(#sky)"/>'
    if mode == "dark":
        body += stars(rng, 380, 620)
        body += '<circle cx="1420" cy="250" r="46" fill="#E6F4F1" opacity="0.9"/><circle cx="1440" cy="238" r="44" fill="#0A1724"/>'
    else:
        body += '<circle cx="1380" cy="560" r="150" fill="#FBD9BE" opacity="0.6" filter="url(#blur)"/><circle cx="1380" cy="560" r="70" fill="#FCE7D6"/>'
    layers = 7
    for i in range(layers):
        t = i / (layers - 1)
        base = lerp(560, 900, t ** 0.9)
        d = ridge(rng, base, lerp(170, 90, t), rough=0.52)
        body += f'<path d="{d}" fill="{mix(back, front, t ** 0.8)}"/>'
        if i < layers - 1:
            body += f'<rect y="{base - 40:.0f}" width="1920" height="160" fill="{mist}" opacity="{0.10 if mode == "dark" else 0.22}" filter="url(#blur)"/>'
    return svg(body + wordmark(text, "#3AA69B"), defs)

# ---------------------------------------------------------------- 2. Still lake (low sun / moon + reflection)
def stilllake(mode):
    rng = random.Random(11)
    hy = 640
    if mode == "dark":
        sky = [(0, "#05080F", 1), (0.7, "#0C1A26", 1), (1, "#123038", 1)]
        water = [(0, "#0D2128", 1), (1, "#03060A", 1)]
        orb, glow, text = "#5EEAD4", "#2DD4BF", "#8A949E"
    else:
        sky = [(0, "#E3ECEF", 1), (0.75, "#F2EDE6", 1), (1, "#F6E2D6", 1)]
        water = [(0, "#E6E4DF", 1), (1, "#C9D6DA", 1)]
        orb, glow, text = "#F07B5A", "#F4A285", "#5B6672"
    defs = vgrad("sky", sky) + vgrad("water", water) + '<filter id="g"><feGaussianBlur stdDeviation="40"/></filter><filter id="s"><feGaussianBlur stdDeviation="1.2"/></filter>'
    body = f'<rect width="1920" height="{hy}" fill="url(#sky)"/><rect y="{hy}" width="1920" height="{H - hy}" fill="url(#water)"/>'
    if mode == "dark": body += stars(rng, 160, 450, maxr=1.2)
    body += f'<circle cx="960" cy="{hy - 150}" r="230" fill="{glow}" opacity="0.18" filter="url(#g)"/>'
    body += f'<circle cx="960" cy="{hy - 150}" r="110" fill="{orb}"/>'
    # broken reflection: bars shrinking and fading with distance
    y = hy + 14
    k = 0
    while y < H - 60:
        t = (y - hy) / (H - hy)
        w = lerp(220, 40, t) * rng.uniform(0.6, 1.15)
        x = 960 - w / 2 + rng.uniform(-14, 14)
        body += f'<rect x="{x:.1f}" y="{y:.1f}" width="{w:.1f}" height="{lerp(5, 3, t):.1f}" rx="2" fill="{orb}" opacity="{lerp(0.75, 0.08, t):.2f}" filter="url(#s)"/>'
        y += lerp(9, 22, t); k += 1
    body += f'<rect y="{hy - 1}" width="1920" height="2" fill="{orb}" opacity="0.25"/>'
    return svg(body + wordmark(text, "#3AA69B" if mode == "dark" else "#1E8F84"), defs)

# ---------------------------------------------------------------- 3. Misty pines
def pine(x, base, h, color):
    w = h * 0.34
    tiers, d = 5, ""
    for i in range(tiers):
        ty = base - h + h * i / tiers * 0.85
        tw = w * (0.35 + 0.65 * (i + 1) / tiers)
        d += f"M{x:.1f} {ty:.1f} L{x - tw:.1f} {ty + h * 0.32:.1f} L{x + tw:.1f} {ty + h * 0.32:.1f} Z "
    d += f"M{x - h * 0.02:.1f} {base - h * 0.1:.1f} h{h * 0.04:.1f} V{base + 4} h{-h * 0.04:.1f} Z"
    return f'<path d="{d}" fill="{color}"/>'
def mistypines(mode):
    rng = random.Random(3)
    if mode == "dark":
        sky = [(0, "#0A1218", 1), (1, "#1F3238", 1)]; fog, far, near, text = "#2A4248", "#1E3238", "#03070A", "#9AA7B1"
    else:
        sky = [(0, "#DCE6E8", 1), (1, "#F3F5F4", 1)]; fog, far, near, text = "#FFFFFF", "#B7C7C9", "#1F3A3C", "#DCE6EA"
    defs = vgrad("sky", sky) + '<filter id="f"><feGaussianBlur stdDeviation="30"/></filter>'
    body = '<rect width="1920" height="1080" fill="url(#sky)"/>'
    rows = 6
    for r in range(rows):
        t = r / (rows - 1)
        base = lerp(560, 1200, t)
        col = mix(far, near, t ** 1.3)
        hmin, hmax = lerp(60, 300, t), lerp(140, 600, t)
        body += f'<rect y="{base - 30:.0f}" width="1920" height="{H - base + 60:.0f}" fill="{col}"/>'
        x = rng.uniform(-40, 0)
        while x < W + 60:
            body += pine(x, base, rng.uniform(hmin, hmax), col)
            x += rng.uniform(0.25, 0.6) * hmax * 0.5
        body += f'<rect y="{base - hmax * 0.6:.0f}" width="1920" height="{hmax * 0.7:.0f}" fill="{fog}" opacity="{(0.25 if mode == "dark" else 0.45) * (1 - t) ** 0.7:.2f}" filter="url(#f)"/>'
    return svg(body + wordmark(text, "#3AA69B"), defs)

# ---------------------------------------------------------------- 4. Aurora
def aurora(mode):
    rng = random.Random(21)
    hy = 780
    if mode == "dark":
        sky = [(0, "#02050A", 1), (0.7, "#081822", 1), (1, "#0E2A30", 1)]
        bands = [("#2DD4BF", "#34D399"), ("#5EEAD4", "#818CF8")]; mtn, water, text, accent, op = "#04080C", "#050E14", "#9AA7B1", "#3AA69B", 1.0
    else:
        sky = [(0, "#BFD3E2", 1), (0.7, "#E6EEF1", 1), (1, "#F4EEE8", 1)]
        bands = [("#14B8A6", "#34D399"), ("#5FC4B8", "#8B9CF8")]; mtn, water, text, accent, op = "#2E4C56", "#D5E0E4", "#2E4C56", "#1E8F84", 0.7
    defs = vgrad("sky", sky) + '<filter id="soft" x="-5%" y="-20%" width="110%" height="140%"><feGaussianBlur stdDeviation="2.2 7"/></filter>'
    defs += '<filter id="haze"><feGaussianBlur stdDeviation="40"/></filter>'
    sky_body = '<rect width="1920" height="1080" fill="url(#sky)"/>'
    if mode == "dark": sky_body += stars(rng, 360, 720)
    for bi, (c0, c1) in enumerate(bands):
        defs += vgrad(f"r{bi}", [(0, c1, 0), (0.6, c0, 0.55), (0.92, c0, 0.95), (1, c0, 0)])
        y0, ph = 330 + bi * 110, bi * 1.9
        curve = lambda x: y0 + 70 * math.sin(x / 300 + ph) + 35 * math.sin(x / 117 + ph * 2)
        sky_body += f'<path d="M0 {curve(0):.0f} ' + " ".join(f"L{x} {curve(x):.0f}" for x in range(0, 1921, 40)) + f'" fill="none" stroke="{c0}" stroke-width="90" opacity="{0.12 * op:.2f}" filter="url(#haze)"/>'
        rays = []
        for x in range(0, 1921, 5):
            env = (0.35 + 0.65 * (0.5 + 0.5 * math.sin(x / 210 + ph * 3))) * (0.6 + 0.4 * rng.random())
            yb = curve(x); h = lerp(120, 300, env)
            rays.append(f'<rect x="{x}" y="{yb - h:.0f}" width="4" height="{h:.0f}" opacity="{env * op:.2f}"/>')
        sky_body += f'<g fill="url(#r{bi})" filter="url(#soft)">' + "".join(rays) + "</g>"
    m = ridge(rng, hy - 150, 130, rough=0.5)
    body = f'<g id="scene">{sky_body}<path d="{m}" fill="{mtn}"/></g>'
    body += f'<defs><clipPath id="lake"><rect y="{hy}" width="1920" height="{H - hy}"/></clipPath></defs>'
    body += f'<g clip-path="url(#lake)"><rect y="{hy}" width="1920" height="{H - hy}" fill="{water}"/><use href="#scene" transform="translate(0 {2 * hy}) scale(1 -1)" opacity="0.4"/></g>'
    return svg(body + wordmark(text, accent), defs)

# ---------------------------------------------------------------- 5. Silk (flowing abstract ribbons)
def silk(mode):
    if mode == "dark":
        bg = [(0, "#04060B", 1), (1, "#0A1220", 1)]; cols = ["#2DD4BF", "#2563EB", "#7C3AED"]; text, accent, op = "#8A949E", "#3AA69B", 0.75
    else:
        bg = [(0, "#F8FAFC", 1), (1, "#E4ECF2", 1)]; cols = ["#0F9F90", "#2F6FE4", "#7C4DEB"]; text, accent, op = "#5B6672", "#1E8F84", 0.6
    defs = vgrad("bg", bg, x2=1, y2=1) + vgrad("rib", [(0, cols[0], 1), (0.5, cols[1], 1), (1, cols[2], 1)], x2=1, y2=0)
    defs += '<filter id="gl"><feGaussianBlur stdDeviation="14"/></filter>'
    body = '<rect width="1920" height="1080" fill="url(#bg)"/>'
    centre = lambda x: 560 + 170 * math.sin(x / 480 + 0.6) - 0.08 * (x - 960)
    width = lambda x: 300 + 120 * math.sin(x / 700 + 1.2)
    twist = lambda x: x / 520 + 0.4
    n, lines = 110, []
    for i in range(n):
        t = i / (n - 1) - 0.5
        pts = [(x, centre(x) + width(x) * t * math.cos(twist(x)) * 1.0 + 60 * t * math.sin(twist(x) * 2)) for x in range(-60, 1981, 30)]
        d = f"M{pts[0][0]} {pts[0][1]:.1f} " + " ".join(f"L{x} {y:.1f}" for x, y in pts[1:])
        edge = 1 - abs(t) * 2
        lines.append(f'<path d="{d}" opacity="{op * (0.18 + 0.82 * edge ** 0.6):.2f}"/>')
    body += f'<g fill="none" stroke="url(#rib)" stroke-width="22" opacity="0.10" filter="url(#gl)">' + lines[n // 2].replace("<path", "<path stroke-width='420'") + "</g>"
    body += '<g fill="none" stroke="url(#rib)" stroke-width="1.4" stroke-linejoin="round">' + "".join(lines) + "</g>"
    return svg(body + wordmark(text, accent), defs)

# ---------------------------------------------------------------- 6. Tide (aerial waves)
def tide(mode):
    rng = random.Random(5)
    if mode == "dark":
        deep, shallow, foam, text = "#04121A", "#0F4C55", "#9FE6DC", "#B6C2CA"
    else:
        deep, shallow, foam, text = "#1E7F8C", "#9EE3DA", "#FFFFFF", "#F2F7F8"
    defs = '<filter id="fb"><feGaussianBlur stdDeviation="2.5"/></filter>'
    body = f'<rect width="1920" height="1080" fill="{deep}"/>'
    bands = 16
    for i in range(bands):
        t = i / (bands - 1)
        y = lerp(-80, 1080, t)
        pts = [(x, y + 40 * math.sin(x / 260 + i * 1.7) + 18 * math.sin(x / 90 + i)) for x in range(-40, 1981, 40)]
        top = " ".join(f"L{x} {yy:.1f}" for x, yy in pts)
        col = mix(deep, shallow, (1 - abs(t - 0.62) / 0.62) ** 1.6 if t <= 1 else 0)
        body += f'<path d="M-40 1100 {top} L1980 1100 Z" fill="{col}"/>'
        foam_d = "M" + " L".join(f"{x} {yy:.1f}" for x, yy in pts)
        body += f'<path d="{foam_d}" fill="none" stroke="{foam}" stroke-width="{rng.uniform(1.5, 4):.1f}" opacity="{rng.uniform(0.25, 0.6):.2f}" filter="url(#fb)"/>'
    return svg(body + wordmark(text, "#5EEAD4" if mode == "dark" else "#FFFFFF"), defs)

for name, fn in dict(ridgeline=ridgeline, **{"still-lake": stilllake, "misty-pines": mistypines}, aurora=aurora, silk=silk, tide=tide).items():
    for mode in ("light", "dark"):
        (OUT / f"{name}-{mode}.svg").write_text(fn(mode))
print("ok")
