# Desktops on node3 (operator-laptop as second hypervisor; changelog #99). Each needs desktops/<name>.sops.yaml
# (./secrets.sh desktop <name>). Stage 3 test: one disposable Standard desktop (ADR 0010), created and destroyed.
desktops = {
  "lv-test18" = { user = "molszewski", memory_mib = 4096, vcpus = 2, guacamole_name = "lv-test18 (node3)" }
}
