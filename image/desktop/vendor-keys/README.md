# Vendor signing keys

Keys for third-party package sources the image build uses, pinned here so the build does not trust whatever a download returns.

| File | Vendor | Primary key fingerprint | Used for |
|---|---|---|---|
| `google-linux-signing-key.pub` | Google (Linux Packages Signing Authority) | `EB4C 1BFD 4F04 2F6D DDCC EC91 7721 F63B D38B 4796` | Google Chrome, the EHR browser (ADR 0016) |

The Containerfile checks the primary fingerprint before it uses the key, and dnf checks the repository metadata and every package against it. Google signs with yearly subkeys (the one current on 2026-10-20 expires 2029-03-09). When Google adds a new signing subkey, the build fails at the Chrome step until this file is refreshed from `https://dl.google.com/linux/linux_signing_key.pub` and its primary fingerprint is checked again.
