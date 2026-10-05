#!/usr/bin/env bash
# idm01 after first boot (changelog #32). Run on idm01 as the admin user (sudo).
set -euo pipefail
C=$(nmcli -t -f NAME,DEVICE con show --active | awk -F: '$2=="enp1s0"{print $1}')
sudo nmcli con mod "$C" ipv6.ignore-auto-dns yes ipv6.dhcp-send-hostname no   # ISP IPv6 DNS arrives despite accept-ra: false
sudo nmcli con up "$C"
sudo dnf -y install firewalld ipa-server ipa-server-dns                       # firewalld is not in the Image Builder base
sudo systemctl enable --now firewalld
sudo firewall-cmd --permanent --remove-service=cockpit
sudo firewall-cmd --permanent --add-service=freeipa-4
sudo firewall-cmd --permanent --add-service=dns
sudo firewall-cmd --reload
sudo dnf -y upgrade
