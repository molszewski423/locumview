# LocumView branding

Installed by `../install-desktop.sh` (target: Ansible `branding` role).

- `locumview-logo.svg`: top-bar logo (white outlined L). Installed as the `fedora-logo-icon` / `system-logo-icon` hicolor icons under `/usr/local/share/icons`, because RHEL's `/etc/os-release` sets `LOGO=fedora-logo-icon`.
- `locumview-gdm-logo.svg`: GDM greeter and lock-screen logo (white L mark + wordmark), from `gen-gdm-logo.py` (needs fontTools). Set via `org.gnome.login-screen logo` in the `local` dconf db, which both the gdm and user profiles read.
- `wallpapers/<name>-{light,dark}.svg`: wallpaper pairs. GNOME switches between them with the light/dark style (`picture-uri` / `picture-uri-dark`). The install script renders each one to a 3840x2160 PNG.

## Regenerating wallpapers

The SVGs are generated. Edit the generator, not the SVG:

| Generator | Designs |
|---|---|
| hand-made | nested (recreation of the original LocumView wallpaper) |
| `gen-wallpapers.py` | viewfinder, pulse, horizon, monogram |
| `gen-scenic.py` | ridgeline, still-lake, misty-pines, aurora, silk, tide |
| `gen-terminal.py` | terminal |

All text is converted to vector outlines in **JetBrains Mono Nerd Font**, so the target desktop needs no extra fonts. This needs `fontTools` and the font files (see `FONT_DIR` in `textpath.py`):

```
python3 gen-wallpapers.py && python3 gen-scenic.py
python3 gen-terminal.py          # needs fontTools
python3 outline-wordmark.py      # needs fontTools; outlines the bottom-left "LocumView" in every SVG
```

Always run `outline-wordmark.py` last. The other generators emit the wordmark as `<text>`.
