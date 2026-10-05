#!/bin/bash
# IdM policy for LocumView desktops (ADR 0006, changelog #36). Idempotent. Run on idm01 after `kinit admin`.
# Host group, login rule (HBAC), sudo rule, default shell; disables IdM's allow_all once the rule exists.
# New desktop: ipa host-add <fqdn> --ip-address=<ip> --password=<one-time>; ipa hostgroup-add-member locumview-desktops --hosts=<fqdn>
set -euo pipefail
ipa config-mod --defaultshell=/bin/bash >/dev/null 2>&1 || true          # IdM's default is /bin/sh
ipa hostgroup-show locumview-desktops >/dev/null 2>&1 || ipa hostgroup-add locumview-desktops --desc="LocumView desktops (ADR 0006)"
if ! ipa hbacrule-show locumview-desktop-login >/dev/null 2>&1; then
  ipa hbacrule-add locumview-desktop-login --desc="LocumView users may log in to LocumView desktops" --servicecat=all
  ipa hbacrule-add-user locumview-desktop-login --groups=locumview-users --groups=locumview-admins
  ipa hbacrule-add-host locumview-desktop-login --hostgroups=locumview-desktops
fi
if ! ipa sudorule-show locumview-admins-desktops >/dev/null 2>&1; then
  ipa sudorule-add locumview-admins-desktops --desc="LocumView admins: full sudo on LocumView desktops" --cmdcat=all --runasusercat=all --runasgroupcat=all
  ipa sudorule-add-user locumview-admins-desktops --groups=locumview-admins
  ipa sudorule-add-host locumview-admins-desktops --hostgroups=locumview-desktops
fi
ipa hbacrule-disable allow_all >/dev/null 2>&1 || true                  # only explicit rules grant logins
ipa hbacrule-find --sizelimit=20 | grep -E "Rule name|Enabled"
