# ADR 0002: Host the access layer on k3s

Status: Accepted
Date: 2026-10-02

## Context

Phase 2 adds the access layer: Apache Guacamole (web app), guacd (the RDP proxy), their database, and Keycloak for SSO and MFA, behind TLS. PLAN.md left the hosting choice open: Podman with Quadlet units on one host, or Kubernetes.

On 2026-10-02 the homelab ran a three-node k3s cluster (v1.36.5+k3s1): node1 (control plane, Debian 13), node2 (Debian 13) and a CentOS Stream 10 worker (`centosbook`). It already provided Traefik as the default ingress controller, `local-path` storage, and Helm. On 2026-10-02 the reference desktop VM moved to node1 on a LAN bridge (changelog #15), so any node can reach it.

## Decision

Run the whole access layer on the existing k3s cluster, in a dedicated `locumview` namespace, deployed from manifests and Helm values committed to this repo. Desktops stay as libvirt VMs (Terraform, Phase 3). Only the access layer is containerised.

## Alternatives considered

- **Podman + Quadlet on a single RHEL host.** Simplest, fully Red Hat-native (systemd units, SELinux), and a good fit for a single-site appliance. Rejected for now: there's no scheduling or failover across hosts, and it doesn't show the Kubernetes skills the project targets. It remains the documented fallback for a small single-host deployment, and the same container images apply.
- **OpenShift / OKD or MicroShift.** The production-grade Red Hat answer, and where an enterprise deployment of LocumView would land. Rejected for the homelab: OpenShift's resource footprint, and MicroShift is single-node. The manifests avoid k3s-specific features apart from the bundled Traefik ingress and local-path storage, both swappable, so moving to OpenShift means replacing the Ingress with Routes and choosing a storage class, not a redesign.
- **KubeVirt for the desktops too.** One control plane for everything. Rejected for version one: GNOME Remote Desktop and Secure Boot/vTPM are already proven on libvirt, and Phase 3 targets Terraform's libvirt provider.

## Consequences

- guacd reaches desktops over the LAN (RDP 3389 on the bridged VM). Once guacd's pod network is known, desktop firewalls must allow RDP only from the k3s nodes (changelog #4 follow-up).
- The cluster nodes are Debian and CentOS Stream, not RHEL. This is a homelab deviation, recorded here. The production reference is RHEL or OpenShift.
- Stateful parts (the Guacamole database, Keycloak's database) start on `local-path` volumes, which tie them to one node. Acceptable for version one; backups are required before any real data.
- Secrets for these workloads are handled per ADR 0003.
- guacd's bundled FreeRDP must handle GNOME Remote Desktop's two consecutive server redirections (changelog #14). This is the first thing to verify once it's deployed.

## Update 2026-10-04

On 2026-10-04 the cluster became two nodes: node1 (control plane) and node2, both Debian 13. The CentOS worker was reinstalled as `suse-laptop`, an openSUSE Leap 16.0 machine for developing the SUSE variant of LocumView, and is no longer a k3s node. The decision is unchanged. The homelab deviation is now Debian only. guacd, Guacamole and Keycloak were rescheduled onto the remaining nodes, and the desktop firewall allowlist drops <suse-laptop-ip> (changelog #29).

## Update 2026-10-28: three nodes, k3s server on node2

The k3s server (control plane, embedded etcd) moved from node1 to node2 on 2026-10-06 (changelog entries of that date). node1 is now an agent, and it is the hypervisor that carries the desktop VMs, which are invisible to the k3s scheduler. node3 (operator-laptop, Fedora 45) joined as a tainted worker and a second hypervisor on 2026-10-28 (changelog #99); test desktops go there first, and nothing schedules on it unless placed. suse-laptop (openSUSE Leap 16.0) is not a cluster node: the CentOS Stream 10 worker it replaced left the cluster in changelog #29 (the update of 2026-10-04 above). Pod traffic between nodes is encrypted over a WireGuard backend (changelog #49).

The cluster is now three nodes: node1 (Debian 13, GPU agent and hypervisor), node2 (Debian 13, k3s server) and node3 (Fedora 45, tainted worker and second hypervisor). The homelab deviation is now Debian and Fedora, not RHEL. Every new or resized desktop VM on node1 still requires raising that node's `system-reserved` by the VM's maximum memory (ADR 0010, update of 2026-10-06). The decision is unchanged.
