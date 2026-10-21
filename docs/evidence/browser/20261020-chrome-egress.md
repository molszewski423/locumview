# Chrome egress audit, 2026-10-20

ADR 0016 says the EHR browser (Google Chrome) is cut off from Google by its managed policies, and that the claim
stays a design goal until it is measured. This is the first measurement. Changelog #60.

## Setup

- Desktop `lv-test14`, built by OpenTofu from a clean clone and running the signed image with Chrome 156.0.8078.47
  and the policies in `image/desktop/files/etc/opt/chrome/policies/managed/` (DISA Chrome STIG settings, no-calls-home
  settings, every address blocked except the EHR's; `hardening/browser/README.md`).
- The IdM user's GNOME session running (headless, as when nobody is connected through Guacamole).
- `tcpdump` on the desktop's network interface, every packet, in two phases:
  - **A, baseline:** 5 minutes, no browser running.
  - **B, Chrome:** 15 minutes with the EHR launcher open in the user's session (Chrome in app mode on the
    "No EHR is set up" page, 6 Chrome processes the whole time), launched the way a user's click launches it.
- Chrome's own sockets sampled every second (`ss -p`) during phase B.
- **Positive control:** the same capture for 90 seconds with Chrome running *without* the managed policies,
  to show the method sees Chrome's traffic when there is some.

## Results

Traffic the desktop sent (SSH from the operator machine excluded), by destination:

| | Phase A, baseline (5 min) | Phase B, Chrome open (15 min) |
|---|---|---|
| IdM server, LDAP (389) and Kerberos (88): SSSD | yes | yes, same pattern |
| NTP servers (123) | yes | yes |
| ARP | yes | yes |
| DNS queries | none | **none** |
| HTTPS (TCP or QUIC 443), any destination | none | **none** |
| Sockets held by Chrome processes (1-second samples) | | **none** |

**Positive control, Chrome without the policies, 90 seconds:** about 46,000 packets, with DNS queries for
`accounts.google.com`, `clients2.google.com`, `clients2.googleusercontent.com`, `clientservices.googleapis.com`,
`update.googleapis.com`, `www.google.com`, `www.gstatic.com`, `redirector.gvt1.com` and a `gvt1.com` download host
(component downloads), `secure.globalsign.com`, and the network's DNS-over-HTTPS resolvers.

**Reading:** with the policies in place, Chrome made no connection at all in 15 minutes, while the same Chrome
without them reached about ten Google services within 90 seconds. The policies, not the test, are what stop it.

## Limits

- 15 minutes, on the EHR launcher's local page, with no EHR configured. A real EHR adds its own sites, which
  the allowlist permits and which this audit does not cover.
- No Safe Browsing traffic was seen either, although Safe Browsing is on at the standard level (ADR 0016, DISA
  DTBC-0038) and is expected to be the one connection to Google. Its list updates may be less frequent than
  15 minutes. A 24-hour capture is the next step before the claim is stated as "Safe Browsing only".
- Headless Chrome cannot be scripted with these policies: `DeveloperToolsAvailability` = 2 (DTBC-0068) also
  blocks the DevTools protocol that headless screenshots use. The policy names were checked against Chromium's
  policy list instead, and `chrome://policy` is now allowed so an administrator can see them in the session.

## Found on the way

The desktop's resolver list included the internet provider's IPv6 DNS servers, learned from router
advertisements, beside the LAN resolver: provisioning had set "DNS from DHCPv4 only" on the installer's network
connection, and cloud-init generated a second connection at the next boot without it. Fixed in the image
(changelog #60): cloud-init no longer configures the network, and a boot-time service sets the rule on every
wired connection.

Addresses of the test network are left out of this record; no packet captures are committed.
