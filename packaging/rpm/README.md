# LocumView RPMs

Phase 4 (changelog #62): LocumView's own desktop pieces as signed RPMs, built in a clean buildroot and published to
the Gitea RPM registry. A public Fedora COPR mirror may follow once the packages are stable.

| Package | Contents |
|---|---|
| `locumview-shell-extensions` | The Activities button, clipboard guard and desktop layout extensions (GPL-2.0-or-later); `/etc/locumview/clipboard.conf` |
| `locumview-branding` | The LocumView logo under the distribution logo's names, in an override directory first in `XDG_DATA_DIRS` (no package's files are changed); the login logo; the wallpapers in light and dark, listed in Settings |
| `locumview-tour` | The LocumView Tour, its autostart at first sign-in, and the guest account's reopen-on-connect service |
| `locumview-ehr-launcher` | The EHR launcher (Chrome app mode), its local start page and `/etc/locumview/ehr.conf` |

All four come from one spec, `locumview-desktop.spec`, built from the same files `packaging/install-desktop.sh` and
the image use, so nothing moved. Dconf defaults, the organization's layout, the STIG and third-party pieces
(Papirus, Tiling Assistant, Blur my Shell) stay with the image for now.

## Build, sign, publish

CI does all three on every change to the packaged files (`.gitea/workflows/rpms.yml`, on the image-build runner; the
key comes from Actions secrets). By hand:

```
packaging/rpm/build-rpms.sh build/rpms            # HEAD; release 1.<commit time, UTC>git<commit>
sops -d packaging/rpm/signing/rpm-signing.sops.yaml | packaging/rpm/sign-rpms.sh build/rpms
REGISTRY_USER=<owner> REGISTRY_TOKEN=<token> packaging/rpm/publish-rpms.sh build/rpms
```

- **Build** runs `rpmbuild` in a CentOS Stream 10 container pinned by digest (`builder.env`), a fresh buildroot every
  time, rootless, needing no Red Hat login. `%check` validates the desktop files and the extension metadata.
- **Sign** with the LocumView RPM signing key (RSA 4096, fingerprint
  `F265 A948 9197 3976 7055  AD28 0F02 A990 167E A18E`, expires 2029-10-21). The private key and its passphrase are
  only in `signing/rpm-signing.sops.yaml`; the script takes them on stdin and keeps them in a tmpfs inside the
  container. Every package is then checked against the committed public key, `signing/RPM-GPG-KEY-locumview`.
- **Publish** refuses any package not signed with that key, then uploads to `https://git.lan/api/packages/<owner>/rpm/el10`.
- **Install** with `locumview.repo` and the public key in `/etc/pki/rpm-gpg/RPM-GPG-KEY-locumview`.

## Checked on the first build

- The packaged files match the files in the current desktop image byte for byte (75 files, wallpapers and icon
  cache included); the only differences are rpmbuild's shebang normalization (`/bin/sh` to `/usr/bin/sh`) and the
  license files.
- Installed into the image with `localpkg_gpgcheck=1` and no network: refused without the public key, installed
  with it, `rpm -V` clean.
- Publishing refuses a package whose signature was removed.
- Installed from the registry with `locumview.repo` (dnf, `gpgcheck` and `repo_gpgcheck` on): the metadata checked
  against the registry's key, each package against the LocumView key. Gitea's own generated `.repo` file is not
  used: it would check the packages against the registry's key, which did not sign them.
