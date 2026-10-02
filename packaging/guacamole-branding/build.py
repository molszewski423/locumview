#!/usr/bin/env python3
"""Build locumview-branding.jar reproducibly (fixed timestamps, sorted entries): same sources, same bytes.
Output: k8s/locumview/guacamole/locumview-branding.jar (mounted into Guacamole via a generated ConfigMap)."""
import pathlib, zipfile
here = pathlib.Path(__file__).resolve().parent
src = here / "src"
out = here.parent.parent / "k8s/locumview/guacamole/locumview-branding.jar"
with zipfile.ZipFile(out, "w", zipfile.ZIP_DEFLATED) as z:
    for f in sorted(p for p in src.rglob("*") if p.is_file()):
        info = zipfile.ZipInfo(str(f.relative_to(src)), date_time=(2026, 1, 1, 0, 0, 0))
        info.external_attr = 0o644 << 16
        info.compress_type = zipfile.ZIP_DEFLATED
        z.writestr(info, f.read_bytes())
print(out, out.stat().st_size)
