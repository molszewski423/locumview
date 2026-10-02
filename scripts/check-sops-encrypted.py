#!/usr/bin/env python3
"""Pre-commit guard (ADR 0003): every *.sops.yaml must really be SOPS-encrypted.

detect-secrets skips *.sops.yaml (encrypted values are false positives), so this check makes sure
such a file can't hold plain text: each document needs a `sops:` metadata block with an age
recipient, and every value under data/stringData must be an ENC[AES256_GCM,...] string.
"""
import sys

import yaml


def check(path):
    errors = []
    with open(path, encoding="utf-8") as f:
        docs = [d for d in yaml.safe_load_all(f) if d is not None]
    if not docs:
        return [f"{path}: empty"]
    for i, doc in enumerate(docs):
        where = f"{path} (document {i + 1})"
        meta = doc.get("sops") if isinstance(doc, dict) else None
        if not isinstance(meta, dict) or not meta.get("age"):
            errors.append(f"{where}: no sops metadata with an age recipient; encrypt with `sops --encrypt --in-place`")
            continue
        for section in ("data", "stringData"):
            for key, value in (doc.get(section) or {}).items():
                if not (isinstance(value, str) and value.startswith("ENC[AES256_GCM,")):
                    errors.append(f"{where}: {section}.{key} is not encrypted")
    return errors


def main(paths):
    errors = [e for p in paths for e in check(p)]
    for e in errors:
        print(e, file=sys.stderr)
    return 1 if errors else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
