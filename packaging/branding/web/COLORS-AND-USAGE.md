# LocumView brand kit

## Colours
| Role | Hex | Use |
|---|---|---|
| Navy (background) | `#0E141C` | page background, app icon tile, dark sections |
| Surface | `#151D28` | cards and panels on navy |
| Teal (accent) | `#5EEAD4` | the "L" in the logo, primary buttons, links, highlights on dark |
| Teal (on light) | `#0F9D8A` | accent on white/light backgrounds (meets contrast better than #5EEAD4) |
| Text on dark | `#E6EDF3` | body text on navy |
| White | `#FFFFFF` | logo outline, headings on dark |

## Files
- `svg/` vector originals (use these in v0 when possible): mark (white / teal / navy), wordmark for dark and light backgrounds, app icon.
- `png/` rasters: mark 64-512 px, app icon 16-512 px (`favicon.ico` included; 180 = apple-touch-icon, 192/512 = web manifest), wordmark at 644 and 1288 px wide.
- `wallpapers/` 1920x1080 hero/background images from the desktop wallpaper set.

## Notes
- The wordmark text is outlined vector paths (JetBrains Mono), so no font is needed to display it.
- Keep clear space around the mark of at least 1/4 of its width; don't recolour the teal "L" except to the on-light teal.
- Source of truth: the LocumView repo, `packaging/branding/` (generated with the scripts there).
