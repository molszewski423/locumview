# Desktops on node1. Each needs desktops/<name>.sops.yaml (./secrets.sh desktop <name> [--demo]).
desktops = {
  # The live demo (login.locumview.com): the owner's desktop plus the guest demo user (port 3391).
  "lv-demo01" = { user = "molszewski", memory_mib = 8192, vcpus = 4, guacamole_groups = ["locumview-admins", "locumview-users"] }
}
