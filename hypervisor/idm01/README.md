# idm01: first Red Hat IdM server

ADR 0006 (and its 2026-10-04/05 updates), changelog #32. Order: `create-idm01.sh` on node1, then `post-boot.sh` and `ipa-install.sh` on idm01, then the AdGuard conditional forward `[/corp.locumview.com/]<idm-ip>` on node2.

| | |
|---|---|
| Host | node1, libvirt `qemu:///system`, bridge `br0` |
| VM | 2 vCPU, 4 GiB (free page reporting on, ADR 0010), 40 GiB, UEFI + Secure Boot, host-passthrough, MAC 52:54:00:4c:56:47 |
| Address | <idm-ip>/22 static (eero reservation), gateway <gateway-ip> |
| Base image | RHEL 10.2 qcow2, Red Hat Image Builder, package mode, no packages, register later; SHA-256 b5a806e00f4338c7f2f1bc678e0e7bb8d9c303094ab9c70c23f2611470a2f8e7 |
| Domain / realm | corp.locumview.com / CORP.LOCUMVIEW.COM, integrated DNS forwarding to AdGuard (<node2-ip>), DNSSEC validation off |
| Secrets | activation key and IdM passwords live outside the repo (owner's machine, 0600); SOPS once Ansible takes over |

Admin login: SSH as `mike` with key only (password login disabled), then `kinit admin`.
