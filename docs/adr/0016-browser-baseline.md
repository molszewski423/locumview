# ADR 0016: Browser baseline: Firefox ESR plus hardened Google Chrome for web EHRs

Status: Accepted
Date: 2026-10-20

## Context

A clinical workspace spends most of its time in a browser, and for a web-delivered EHR the browser is part of the vendor's supported configuration. Until now the desktop had one browser: Firefox ESR, which RHEL 10 delivers as a Flatpak from Red Hat's own remote (`redhat-flatpak-preinstall-firefox`; on image-built desktops installed at first boot once the desktop is registered, changelog #56). Web EHRs are validated almost entirely on Chromium browsers, and a hospital IT team can reject a platform for running a browser that is not on the vendor's list even if it works, so being on the list matters as much as working.

## Decision

- **Firefox ESR stays the default system browser.** It ships with RHEL, Red Hat supports it, and it is native to the platform.
- **Google Chrome ships alongside it as the browser that opens the web EHR**, ideally in app or kiosk mode, from Google's official Linux RPM repository.
- **The browser is a swappable default-app slot**, like the other default apps (image/desktop/README.md, "Default apps"). Per deployment, the EHR browser matches the customer's standard browser if Chrome is a problem for them.
- **Hardening:** Chrome is locked down with managed policy files in `/etc/opt/chrome/policies/managed/` (the documented Linux location), following the DISA Google Chrome STIG's settings, and the desktop's egress firewall limits where it can connect. Firefox ESR keeps its own enterprise policies.
- **No calls home:** the policies turn off sync and browser sign-in (`SyncDisabled`, `BrowserSignin` = 0), usage and crash reporting (`MetricsReportingEnabled` = false), search suggestions (`SearchSuggestEnabled`), URL-keyed data collection (`UrlKeyedAnonymizedDataCollectionEnabled`), the spelling service (`SpellCheckServiceEnabled`), alternate error pages (`AlternateErrorPagesEnabled`), network prediction (`NetworkPredictionOptions` = 2), translation (`TranslateEnabled`), field trials (`ChromeVariations` = 2), component updates (`ComponentUpdatesEnabled`; Chrome is updated with the image), background mode (`BackgroundModeEnabled`), the password manager (`PasswordManagerEnabled`), generative AI features (`GenAiDefaultSettings` = 2), WebRTC event log upload (`WebRtcEventLogCollectionAllowed`) and Safe Browsing extended reporting (`SafeBrowsingExtendedReportingEnabled`).
- **Safe Browsing stays on at the standard level** (`SafeBrowsingProtectionLevel` = 1), because the STIG requires it (DTBC-0038). It is the one deliberate connection to Google: Chrome downloads Google's list of dangerous sites and checks partial hashes of URLs against it. A deployment that must have no Google traffic at all can set it to 0 and record a STIG exception.
- **Proof, planned:** Chrome's outbound traffic is captured and audited with these policies in place, and the result is published in this repository. Until then the claim is a design goal, not a verified fact. Pitch line, once verified: "We use the browser your EHR vendor certifies, and we've verifiably cut it off from Google."

## Rationale

- Web-delivered EHRs are validated almost entirely on Chromium browsers: Epic's web Hyperspace, Oracle Health's web Millennium, and MEDITECH Expanse (Chrome and Edge, plus Safari on iPad). Firefox usually isn't on these vendors' supported lists.
- Target customers already standardize on Chromium browsers; the hospitals the owner knows from clinical work run Chrome and Edge.
- Hardening is comparable. DISA publishes STIGs for both Google Chrome and Mozilla Firefox, and both browsers are locked down with managed policy files.
- Data sovereignty is about where data goes, not who wrote the browser. Shipping a Google product is in tension with the sovereignty pitch, which is why the policies and the egress rules above are part of the decision, not an afterthought.

## Facts checked (2026-10-20)

- **DISA STIGs:** Google Chrome Current Windows STIG V2R11 (46 checks), Mozilla Firefox STIG V6R9 (DISA lists a Windows benchmark; Linux and macOS variants exist, V6R7 audits), Microsoft Edge STIG V2R5 (April 2026). The Chrome and Edge STIGs are written for Windows (Group Policy and registry); on Linux the same settings are applied as policy JSON. Not confirmed on cyber.mil directly (its pages did not load); versions taken from Tenable's audit library, STIG Viewer and NIST's National Checklist Program.
- **Chrome on RHEL is not supported by Google.** Google's requirements list Ubuntu 18.04+, Debian 10+, openSUSE 15.5+ and Fedora Linux 39+, and state that "Google does not provide support if you install Chrome on any system that does not meet the specified criteria." The RPM is the one Fedora and openSUSE use; it runs on RHEL, unsupported.
- **Policy names and values** were checked against Chromium's policy definitions (components/policy/resources/templates/policy_definitions): all of the above exist and are current; `MetricsReportingEnabled` covers both usage and crash reports.
- **Policy path:** `/etc/opt/chrome/policies/managed/` (mandatory) and `/etc/opt/chrome/policies/recommended/`, per Google's Linux documentation; it is in `/etc`, which image updates merge. Chrome itself installs to `/opt/google/chrome`, which is part of the read-only image on RHEL 10 image mode, so Chrome's own updater cannot run and updates arrive with the image.
- **Not confirmed:** the EHR vendors' current supported-browser lists (not public for Epic and Oracle Health), and whether they list Chrome on Linux at all; vendor lists typically name the operating system too, often Windows and macOS only. This is the main open question for any EHR deployment and is asked of each vendor per customer.

## Alternatives considered

- **Firefox only.** Rejected: the EHR-certification and hospital-acceptance risk.
- **EPEL Chromium.** Kept as an opt-in for customers who won't accept any Google software, with the tradeoffs documented: community support only, and EPEL packages are outside Red Hat support.
- **Microsoft Edge as the EHR browser.** Edge has a Linux RPM and is on the EHR vendors' lists. Not the default because Chrome is the more common standard among the target hospitals; offered per customer. (Its STIG is Windows-oriented, but so is Chrome's, so that is not a difference between them.)

## Consequences

- **Support:** Red Hat supports Firefox ESR. Chrome on RHEL is supported by neither Red Hat nor Google; LocumView owns it, and the EHR vendor's statement of support covers only the browser, not the operating system.
- Chrome adds a third-party package source to the image build (Google's RPM repository, signed with Google's key) and must be rebuilt into the image at least as often as Chrome's release cycle (every four weeks, plus security releases) to stay a supported version (STIG DTBC-0050).
- The outbound traffic audit and the published result are prerequisites for using the sovereignty pitch line.
