# ADR 0010: Desktop VM sizing tiers and host memory overcommit

Status: Accepted
Date: 2026-10-05

## Context

PLAN.md listed "set VM memory limits on MikePC" as a pending decision, and ADR 0006 (update of 2026-10-05) held back further desktop VMs on MikePC until it was made.

MikePC is a Ryzen 7 7800X3D (8 cores, no SMT, so 8 threads) with 30 GiB of RAM, shared with k3s (the access layer) and the local AI stack. On 2026-10-05 it ran two VMs:

| VM | Allocated | Used in guest | Held by the host (qemu RSS) | Load |
|---|---|---|---|---|
| locumview-ref-dev | 4 vCPU / 8 GiB | 2.6 GiB | 6.9 GiB | 0.00 |
| idm01 | 2 vCPU / 4 GiB | 1.5 GiB | 3.7 GiB | 0.00 |

CPU was not the constraint. Memory was: about 10.6 GiB of host RAM was held for about 4 GiB of real use, because a page a guest has touched once (boot, page cache) stays backed by the host for good. The balloon device had no free page reporting, and KSM was off. At 8 GiB per desktop there was room for about one more.

## Decision

1. **Free page reporting on every VM** (`<memballoon model='virtio' freePageReporting='on'>` with a 10-second stats period). The guest hands pages it frees back to the host, so host usage follows real use instead of the allocation. RHEL 10 guests support it (`CONFIG_PAGE_REPORTING=y`); libvirt 11.3 and QEMU 10.0 on MikePC do too. Guest page cache is still held while the guest keeps it, so the gain depends on workload.
2. **KSM always on** (`/etc/tmpfiles.d/locumview-ksm.conf`: `run=1`, kernel KSM advisor `scan-time`, `use_zero_pages=1`). Desktops come from one image, so many of their pages are identical. ksmtuned was not used: it only turns KSM on under memory pressure, and density is the point here.
3. **Desktop tiers:**

   | Tier | vCPU | Memory | For |
   |---|---|---|---|
   | Standard | 2 | 4 GiB | Browser, office, EHR web clients (default) |
   | Power | 4 | 8 GiB | Developers, heavy native apps; the reference VM |

   No CPU pinning. vCPUs may be overcommitted up to 3:1 across desktops, which is normal for idle-heavy VDI. Memory may be overcommitted only as far as reporting and KSM actually return it; check host `MemAvailable` before adding desktops.
4. **Infrastructure VMs stay fixed:** idm01 keeps 4 GiB (Red Hat's minimum for a small deployment) and gets free page reporting, but no balloon target below its allocation.
5. **Host reserve:** 8 GiB of MikePC stays for the host, k3s and the AI stack.

Applied by `hypervisor/mikepc-memory.sh` (changelog #37). Terraform and the KubeVirt rung must carry the same settings: free page reporting on the balloon device, and KSM on the node.

## Capacity

30 GiB, minus 8 GiB reserve, minus 4 GiB for idm01, leaves about 18 GiB for desktops. That's four Standard desktops at full allocation, and an estimated 6 to 8 concurrent light users with reporting and KSM, because an idle GNOME session holds about 2.5 to 3 GiB. Above that, CPU becomes the limit: RDP encoding is done in software on the host (no GPU). These numbers are estimates until a load test with several concurrent sessions is recorded.

## Consequences

- KSM opens a known cross-VM side channel (page deduplication timing). Accepted for a single-tenant deployment where every desktop belongs to the same organization. A multi-tenant deployment must turn KSM off or limit merging to VMs of one tenant.
- KSM costs some host CPU for scanning; the advisor caps it.
- Changing the balloon device needs a full power-off of the VM, not a guest reboot.
- Moving idm01 to debianbox (ADR 0006's original placement) would free another 4 GiB on MikePC; it stays where it is until the replica exists.

## Alternatives considered

- **Lower allocations only:** less wasted memory, but a desktop still grows to its allocation and keeps it.
- **Hugepages:** better TLB behavior, but hugepage-backed memory can't be shared or reported back, which defeats overcommit.
- **Balloon targets managed by a daemon:** more control, more moving parts; free page reporting gives most of the benefit with none.

## Update 2026-10-05: proof-of-concept target and scale-up path

Owner decision, 2026-10-05.

- **Measured after the change (20:37 to 21:07):** MikePC `MemAvailable` 17.3 GiB (about 12 before); qemu RSS about 2.8 GiB each for locumview-ref-dev and idm01; KSM saving about 0.95 GiB with two guests.
- **Target:** MikePC as it is (32 GB) carries the proof of concept: **5 dedicated desktops comfortably, 6 at the edge** (counting locumview-ref-dev), after keeping about 4 GiB spare for the AI stack. That is enough for the proof of concept; nothing is bought until a trigger below fires.
- **Scale-up triggers,** with everyone signed in: `MemAvailable` stays below about 4 GiB; load average stays near 8 (all threads busy) or users notice input lag; or more than 6 concurrent users are actually needed.
- **Scale-up path, in order:**
  1. A second 2×16 GB kit of the installed part (CMH32GX5M2M6000Z36) in MikePC's two empty slots (B850 board, 4 slots, 128 GB maximum) → 64 GB.
  2. **Multi-session desktops:** several users' private GNOME sessions per RHEL VM (GRD system mode, IdM accounts, per-user systemd slice limits), 6 to 8 users per VM, with dedicated VMs kept for users who need them. Estimated 15 to 20 concurrent office users on 64 GB, where CPU (8 threads) and memory meet. Needs its own ADR.
  3. More cores (a 16-core AM5 CPU) or a second host if CPU is the limit.
- **Alternatives priced 2026-10-05:** DDR5 and DDR4 prices are high (96 GB DDR5 kits about $750 to $1,900; 128 GB DDR4 for a used HP Z440 about $735 to $1,120), so the path favors fewer GiB per user over more hardware. A one-hour cloud test is the cheapest way to show 20 concurrent sessions without owning the hardware (Phase 7, budget alarm first).
- **Still open:** the load test (6 to 8 IdM test users, Firefox and ONLYOFFICE) that replaces these estimates with measurements.
