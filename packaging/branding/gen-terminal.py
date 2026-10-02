#!/usr/bin/env python3
"""LocumView 'Terminal' wallpaper: a shell prompt set in JetBrains Mono Nerd Font (outlined to paths)."""
import random, pathlib, sys
sys.path.insert(0, str(pathlib.Path(__file__).parent))
from textpath import text_path, width
OUT = pathlib.Path(__file__).parent / "wallpapers"

LOG = ["[  OK  ] Started gnome-remote-desktop.service - GNOME Remote Desktop.",
       "[  OK  ] Reached target graphical.target - Graphical Interface.",
       "rdp: TLS fingerprint 58:07:51:ee:bb:c2:d9:33:eb:f6:a9:24",
       "selinux: enforcing  policy: targeted  crypto-policy: DEFAULT",
       "firewalld: services rdp ssh dhcpv6-client",
       "secureboot: enabled  tpm: /dev/tpmrm0  firmware: UEFI",
       "dconf: db local updated (10-locumview-branding)",
       "gdm: remote login session opened for molszewski",
       "subscription-manager: Overall Status: Registered",
       "kernel: 6.12.0-211.61.1.el10_2.x86_64 x86_64 GNU/Linux"]

def build(mode):
    rng = random.Random(42)
    if mode == "dark":
        bg0, bg1, fg, dim, teal, glow, wm, wmacc = "#05080E", "#0B1520", "#E6EDF3", "#7B8A99", "#2DD4BF", "#14B8A6", "#8A949E", "#3AA69B"
        logop = 0.07
    else:
        bg0, bg1, fg, dim, teal, glow, wm, wmacc = "#F5F7FA", "#E6EDF2", "#0E1A26", "#5B6672", "#0F9F90", "#5FC4B8", "#5B6672", "#1E8F84"
        logop = 0.09
    out = [f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1920 1080" width="3840" height="2160">',
           f'<defs><radialGradient id="bg" cx="0.5" cy="0.45" r="0.8"><stop offset="0" stop-color="{bg1}"/><stop offset="1" stop-color="{bg0}"/></radialGradient>',
           f'<radialGradient id="glow" cx="960" cy="540" r="520" gradientUnits="userSpaceOnUse"><stop offset="0" stop-color="{glow}" stop-opacity="0.16"/><stop offset="1" stop-color="{glow}" stop-opacity="0"/></radialGradient>',
           '<linearGradient id="fade" x1="0" x2="1"><stop offset="0" stop-color="#fff" stop-opacity="1"/><stop offset="0.75" stop-color="#fff" stop-opacity="0.4"/><stop offset="1" stop-color="#fff" stop-opacity="0"/></linearGradient>',
           '<mask id="m"><rect width="1920" height="1080" fill="url(#fade)"/></mask>',
           f'<filter id="cg"><feGaussianBlur stdDeviation="10"/></filter></defs>',
           '<rect width="1920" height="1080" fill="url(#bg)"/><rect width="1920" height="1080" fill="url(#glow)"/>']
    # faint boot/log scroll on the left, fading out to the right
    log_d, y = [], 120
    while y < 900:
        line = rng.choice(LOG)
        d, _ = text_path(line, 90, y, 17, "Light")
        log_d.append(d); y += 34
    out.append(f'<path d="{" ".join(log_d)}" fill="{dim}" opacity="{logop}" mask="url(#m)"/>')
    # centred prompt:  ~ ❯ locumview█
    size = 96
    parts = [("~ ", dim, "Regular"), ("❯ ", teal, "Bold"), ("locumview", fg, "Medium")]
    total = sum(width(t, size, w) for t, _, w in parts) + size * 0.6
    x, base = 960 - total / 2, 560
    for t, c, w in parts:
        d, adv = text_path(t, x, base, size, w)
        out.append(f'<path d="{d}" fill="{c}"/>'); x += adv
    cur_w, cur_h = size * 0.56, size * 1.05
    out.append(f'<rect x="{x + 6:.1f}" y="{base - cur_h * 0.82:.1f}" width="{cur_w:.1f}" height="{cur_h:.1f}" rx="4" fill="{teal}" opacity="0.55" filter="url(#cg)"/>')
    out.append(f'<rect x="{x + 6:.1f}" y="{base - cur_h * 0.82:.1f}" width="{cur_w:.1f}" height="{cur_h:.1f}" rx="4" fill="{teal}"/>')
    sub = "virtual desktop · rhel 10 · gnome"
    d, _ = text_path(sub, 960 - width(sub, 26, "Regular", 2) / 2, base + 80, 26, "Regular", tracking=2)
    out.append(f'<path d="{d}" fill="{dim}"/>')
    # bottom-left brand (same mark as the other wallpapers; text in JetBrains Mono)
    out.append(f'''<g transform="translate(70 970)"><rect x="1.5" y="1.5" width="31" height="31" rx="7" fill="none" stroke="{wm}" stroke-width="2.2"/>
<path d="M12 8 V24 H24" fill="none" stroke="{wmacc}" stroke-width="2.6" stroke-linecap="round" stroke-linejoin="round"/></g>''')
    d, _ = text_path("LocumView", 114, 995, 25, "Medium", tracking=0.5)
    out.append(f'<path d="{d}" fill="{wm}"/>')
    out.append("</svg>\n")
    return "\n".join(out)

for mode in ("light", "dark"):
    (OUT / f"terminal-{mode}.svg").write_text(build(mode))
print("ok")
