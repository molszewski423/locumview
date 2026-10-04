#!/usr/bin/env python3
"""Generate the LocumView Tour illustrations (SVG, brand palette). Deterministic: same code, same files."""
import pathlib
import re

NAVY, SURFACE, LINE, TEAL, TEXT, MUTED = "#0E141C", "#151D28", "#2A3644", "#5EEAD4", "#E6EDF3", "#9AA7B4"
OUT = pathlib.Path(__file__).resolve().parent / "art"
W, H = 480, 220


def svg(body):
    return (f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {W} {H}" width="{W*2}" height="{H*2}">'
            f'<rect width="{W}" height="{H}" rx="18" fill="{SURFACE}"/>{body}</svg>\n')


def mark(x, y, s=1.0, stroke="#FFFFFF"):
    return (f'<g transform="translate({x} {y}) scale({s})">'
            f'<rect x="0" y="0" width="26" height="26" rx="6.5" fill="none" stroke="{stroke}" stroke-width="2.4"/>'
            f'<path d="M8.5 6 V19.5 H19" fill="none" stroke="{TEAL}" stroke-width="2.8" stroke-linecap="round" stroke-linejoin="round"/></g>')


def dots(x, y, active=0, n=3):
    out, cx = [], x
    for i in range(n):
        w = 22 if i == active else 8
        out.append(f'<rect x="{cx}" y="{y}" width="{w}" height="8" rx="4" fill="{TEAL if i == active else MUTED}"/>')
        cx += w + 7
    return "".join(out)


def text(x, y, s, size=14, fill=TEXT, anchor="middle", weight="600"):
    return (f'<text x="{x}" y="{y}" font-family="Cantarell, Inter, sans-serif" font-size="{size}" font-weight="{weight}" '
            f'fill="{fill}" text-anchor="{anchor}">{s}</text>')


def corner():
    b = f'<rect x="24" y="26" width="432" height="44" rx="10" fill="{NAVY}" stroke="{LINE}"/>'
    b += f'<rect x="32" y="32" width="118" height="32" rx="16" fill="#1E2A38" stroke="{TEAL}" stroke-width="1.5"/>'
    b += mark(42, 35, 1.0) + dots(78, 44, 0)
    b += text(250, 54, "Mon 9:41", 13, MUTED, weight="500")
    b += f'<path d="M92 82 l0 40" stroke="{TEAL}" stroke-width="2" stroke-dasharray="4 4"/>'
    b += text(92, 146, "Click: overview + app search", 14) + text(92, 168, "Scroll: switch workspace", 14, MUTED, weight="500")
    b += text(330, 146, "The wide dot is the", 14, MUTED, weight="500") + text(330, 168, "workspace you're on", 14, MUTED, weight="500")
    return svg(b)


def workspaces():
    b = ""
    for i, x in enumerate((40, 180, 320)):
        act = i == 1
        b += f'<rect x="{x}" y="40" width="120" height="80" rx="10" fill="{NAVY}" stroke="{TEAL if act else LINE}" stroke-width="{2.5 if act else 1.5}"/>'
        b += f'<rect x="{x+14}" y="56" width="{60 if i != 2 else 40}" height="40" rx="5" fill="{"#1E2A38" if not act else "#1F3B3B"}"/>'
        b += text(x + 60, 145, f"Alt+{i+1}", 15, TEAL if act else TEXT)
    b += text(240, 190, "Alt+PgUp / Alt+PgDn: previous / next", 14, MUTED, weight="500")
    return svg(b)


def tiling():
    b = f'<rect x="120" y="22" width="240" height="150" rx="10" fill="{NAVY}" stroke="{LINE}"/>'
    for (x, y, k) in ((124, 26, "I"), (242, 26, "O"), (124, 99, "K"), (242, 99, "L")):
        b += f'<rect x="{x}" y="{y}" width="114" height="69" rx="6" fill="#1E2A38" stroke="{TEAL}" stroke-width="1.2" stroke-opacity="0.6"/>'
        b += f'<rect x="{x+38}" y="{y+18}" width="38" height="32" rx="6" fill="{SURFACE}" stroke="{TEAL}" stroke-width="1.5"/>'
        b += text(x + 57, y + 40, k, 16, TEAL)
    b += text(240, 200, "Alt + I / O / K / L", 15)
    return svg(b)


def dock():
    b = f'<rect x="40" y="30" width="400" height="110" rx="12" fill="{NAVY}" stroke="{LINE}"/>'
    b += f'<rect x="110" y="150" width="260" height="50" rx="16" fill="#1E2A38" stroke="{LINE}"/>'
    labels = ("Files", "Calc", "Office", "Web", "Apps")
    for i, lab in enumerate(labels):
        x = 124 + i * 50
        fill = TEAL if i == 4 else ("#3A4858" if i % 2 else "#2F5F66")
        b += f'<rect x="{x}" y="158" width="34" height="34" rx="9" fill="{fill}"/>'
    b += text(240, 80, "Your pinned apps live in the dock", 15)
    b += text(240, 104, "It hides when a window needs the room", 13, MUTED, weight="500")
    return svg(b)


def keys():
    def cap(x, y, s, w):
        return (f'<rect x="{x}" y="{y}" width="{w}" height="40" rx="9" fill="{NAVY}" stroke="{TEAL}" stroke-width="1.6"/>'
                + text(x + w / 2, y + 26, s, 16))
    b = cap(120, 46, "Alt", 76) + text(214, 73, "+", 18, MUTED) + cap(232, 46, "Enter", 96)
    b += text(370, 73, "terminal", 14, MUTED, anchor="start", weight="500")
    b += cap(70, 120, "Ctrl", 76) + text(164, 147, "+", 18, MUTED) + cap(182, 120, "Alt", 76)
    b += text(276, 147, "+", 18, MUTED) + cap(294, 120, "Q", 56) + text(370, 147, "lock", 14, MUTED, anchor="start", weight="500")
    return svg(b)


def menu():
    b = f'<rect x="40" y="24" width="400" height="172" rx="12" fill="{NAVY}" stroke="{LINE}"/>'
    b += f'<rect x="40" y="24" width="150" height="172" rx="12" fill="#1E2A38" stroke="{TEAL}" stroke-width="1.5"/>'
    for i, lab in enumerate(("Clipboard", "On-screen keyboard", "Text input", "Disconnect")):
        b += text(56, 58 + i * 34, lab, 13, TEXT if i < 3 else MUTED, anchor="start", weight="500")
    b += f'<path d="M210 110 h60" stroke="{TEAL}" stroke-width="2" marker-end="url(#a)"/>'
    b += ('<defs><marker id="a" markerWidth="8" markerHeight="8" refX="6" refY="4" orient="auto">'
          f'<path d="M0 0 L8 4 L0 8 z" fill="{TEAL}"/></marker></defs>')
    b += text(350, 96, "Ctrl+Alt+Shift", 15, TEAL) + text(350, 122, "or swipe in from the", 13, MUTED, weight="500")
    b += text(350, 142, "left edge on a phone", 13, MUTED, weight="500")
    return svg(b)


def layout():
    def screen(x, label, style):
        w = 132
        b = f'<rect x="{x}" y="40" width="{w}" height="104" rx="10" fill="{NAVY}" stroke="{LINE}"/>'
        b += f'<rect x="{x+4}" y="44" width="{w-8}" height="9" rx="3" fill="#1E2A38"/>'
        b += f'<rect x="{x+24}" y="62" width="{w-48}" height="48" rx="5" fill="#1E2A38" stroke="{LINE}"/>'
        if style == "mac":       # buttons left, centred dock
            for i in range(3):
                b += f'<circle cx="{x+31+i*7}" cy="68" r="2.4" fill="{MUTED}"/>'
            b += f'<rect x="{x+38}" y="122" width="56" height="15" rx="6" fill="#1E2A38" stroke="{TEAL}" stroke-width="1.2"/>'
            for i in range(4):
                b += f'<rect x="{x+43+i*12}" y="125" width="8" height="9" rx="2" fill="{TEAL if i == 0 else MUTED}"/>'
        elif style == "windows": # buttons right, full-width taskbar
            for i in range(3):
                b += f'<circle cx="{x+w-45+i*7}" cy="68" r="2.4" fill="{MUTED}"/>'
            b += f'<rect x="{x+4}" y="126" width="{w-8}" height="13" rx="3" fill="#1E2A38" stroke="{TEAL}" stroke-width="1.2"/>'
            for i in range(5):
                b += f'<rect x="{x+9+i*12}" y="129" width="8" height="7" rx="2" fill="{TEAL if i == 0 else MUTED}"/>'
        else:                    # GNOME: overview, close button only, no dock
            b += f'<circle cx="{x+w-31}" cy="68" r="2.4" fill="{MUTED}"/>'
            b += f'<rect x="{x+8}" y="45.5" width="16" height="6" rx="3" fill="{TEAL}"/>'
        return b + text(x + w / 2, 168, label, 14, TEXT)
    b = screen(24, "Mac style", "mac") + screen(174, "Windows style", "windows") + screen(324, "GNOME style", "gnome")
    b += text(240, 202, "Set by your organization", 12, MUTED, weight="500")
    return svg(b)


def done():
    b = mark(170, 78, 2.4) + text(250, 125, "Ready", 28, TEXT, anchor="start")
    return svg(b)


def welcome():
    # The wordmark (packaging/branding/locumview-gdm-logo.svg, viewBox 161x48) centred on the card.
    src = (OUT.parent.parent / "branding/locumview-gdm-logo.svg").read_text()
    inner = re.search(r"<svg[^>]*>(.*)</svg>", src, re.S).group(1)
    return svg(f'<g transform="translate({(W - 161 * 1.9) / 2:.1f} {(H - 48 * 1.9) / 2:.1f}) scale(1.9)">{inner}</g>')


OUT.mkdir(exist_ok=True)
for name, fn in (("welcome", welcome), ("corner", corner), ("workspaces", workspaces), ("tiling", tiling), ("dock", dock), ("layout", layout),
                 ("keys", keys), ("menu", menu), ("done", done)):
    (OUT / f"{name}.svg").write_text(fn())
print("art:", sorted(p.name for p in OUT.glob("*.svg")))
