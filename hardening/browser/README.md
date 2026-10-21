# Browser hardening (ADR 0016)

Image-built desktops ship two browsers, each a default-app slot (image/desktop/README.md, "Default apps"):

- **Firefox ESR**, the system browser: Red Hat's Flatpak, enterprise policies in `/etc/firefox/policies/policies.json`.
- **Google Chrome**, the EHR browser: Google's RPM in the image, managed policies in `/etc/opt/chrome/policies/managed/`, opened by the EHR launcher in app mode.

Both policy sets are files in the image (`image/desktop/files/etc/`). They are in `/etc`, so an image update brings new defaults and a deployment can change them on the desktop.

## Google Chrome

### DISA Google Chrome STIG

The settings follow the DISA Google Chrome Current Windows STIG V2R11 (published 2025-05-15). The STIG is written for Windows Group Policy; on Linux the same policies are set in JSON. The table lists the 36 checks in DISA's SCAP benchmark for V2R11, as published by a third-party mirror (cyber.trackr.live); cyber.mil itself did not load. The remaining checks of the full STIG are manual ones, such as running a supported version (see "Updates" below).

File: `10-locumview-stig.json`, unless noted.

| Check | Requirement | Policy | Value |
|---|---|---|---|
| DTBC-0001 | Firewall traversal from remote host disabled | `RemoteAccessHostFirewallTraversal` | false |
| DTBC-0002 | Sites cannot track location | `DefaultGeolocationSetting` | 2 |
| DTBC-0004 | Pop-ups disabled | `DefaultPopupsSetting` | 2 |
| DTBC-0005 | Extensions blocklisted by default | `ExtensionInstallBlocklist` | `["*"]` |
| DTBC-0006 | Approved extensions allowlisted | `ExtensionInstallAllowlist` | not set: no extension is approved |
| DTBC-0007, DTBC-0009 | Default search provider set and enabled | `DefaultSearchProviderEnabled` | false: **exception**, below |
| DTBC-0011 | Password manager disabled | `PasswordManagerEnabled` | false |
| DTBC-0017 | Background processing disabled | `BackgroundModeEnabled` | false |
| DTBC-0020 | Google sync disabled | `SyncDisabled` | true |
| DTBC-0021 | `javascript:` URLs blocked | `URLBlocklist` (`50-locumview-ehr-sites.json`) | includes `javascript://*` |
| DTBC-0023 | Cloud print sharing disabled | `CloudPrintProxyEnabled` | not set: Google Cloud Print was shut down and the policy removed from Chrome |
| DTBC-0025 | Network prediction disabled | `NetworkPredictionOptions` | 2 |
| DTBC-0026 | Metrics reporting disabled | `MetricsReportingEnabled` | false |
| DTBC-0027 | Search suggestions disabled | `SearchSuggestEnabled` | false |
| DTBC-0029 | Importing saved passwords disabled | `ImportSavedPasswords` | false |
| DTBC-0030 | Incognito mode disabled | `IncognitoModeAvailability` | 1 |
| DTBC-0037 | Online revocation checks | `EnableOnlineRevocationChecks` | true |
| DTBC-0038 | Safe Browsing enabled | `SafeBrowsingProtectionLevel` | 1 (standard) |
| DTBC-0039 | Browser history saved | `SavingBrowserHistoryDisabled` | false |
| DTBC-0045 | Session-only cookies | `DefaultCookiesSetting` | 4 |
| DTBC-0052 | Deleting browser history disabled | `AllowDeletingBrowserHistory` | false |
| DTBC-0053 | Prompt for download location | `PromptForDownloadLocation` | true |
| DTBC-0055 | Download restrictions | `DownloadRestrictions` | 1 (block dangerous files) |
| DTBC-0057 | Safe Browsing extended reporting disabled | `SafeBrowsingExtendedReportingEnabled` | false |
| DTBC-0058 | WebUSB disabled | `DefaultWebUsbGuardSetting` | 2 |
| DTBC-0063 | Google Cast disabled | `EnableMediaRouter` | false |
| DTBC-0064 | Autoplay disabled | `AutoplayAllowed` | false |
| DTBC-0066 | URL-keyed anonymized data collection disabled | `UrlKeyedAnonymizedDataCollectionEnabled` | false |
| DTBC-0067 | WebRTC event log collection disabled | `WebRtcEventLogCollectionAllowed` | false |
| DTBC-0068 | Developer tools disabled | `DeveloperToolsAvailability` | 2 |
| DTBC-0069 | Guest mode disabled | `BrowserGuestModeEnabled` | false |
| DTBC-0070 | Credit card autofill disabled | `AutofillCreditCardEnabled` | false |
| DTBC-0071 | Address autofill disabled | `AutofillAddressEnabled` | false |
| DTBC-0072 | Importing autofill data disabled | `ImportAutofillFormData` | false |
| DTBC-0074 | QUIC disabled | `QuicAllowed` | false |

Also set, from earlier STIG releases: `DefaultNotificationsSetting` = 2 (no site notifications).

**Exception, DTBC-0007 and DTBC-0009 (default search provider).** The STIG wants an organization-approved encrypted search provider. Chrome is the EHR browser here and opens only the EHR's sites, so it has no search provider at all: typing in the address bar cannot send text to a search engine. A deployment that uses Chrome as a general browser sets `DefaultSearchProviderEnabled`, `DefaultSearchProviderName` and `DefaultSearchProviderSearchURL` to its approved provider.

### No calls home (ADR 0016)

Beyond the STIG: `BrowserSignin` 0, `SpellCheckServiceEnabled` false, `AlternateErrorPagesEnabled` false, `TranslateEnabled` false, `ChromeVariations` 2 (no field trials), `ComponentUpdatesEnabled` false (Chrome updates with the image), `GenAiDefaultSettings` 2, `BrowserNetworkTimeQueriesEnabled` false, `UserFeedbackAllowed` false, `PromotionalTabsEnabled` false, `ShoppingListEnabled` false, `DefaultBrowserSettingEnabled` false (Firefox stays the default browser), `CloudReportingEnabled` false, `SafeBrowsingSurveysEnabled` false, `SafeBrowsingDeepScanningEnabled` false, the four Privacy Sandbox policies off, `DnsOverHttpsMode` off and `BuiltInDnsClientEnabled` false (names are looked up through the desktop's own resolver, the organization's DNS).

Safe Browsing stays on at the standard level, because the STIG requires it (DTBC-0038): Chrome downloads Google's list of dangerous sites and checks partial hashes of URLs against it. A deployment that must have no Google traffic at all sets `SafeBrowsingProtectionLevel` to 0 and records it as an exception to DTBC-0038.

Every policy name in both files was checked against Chromium's policy list (`components/policy/resources/templates/policies.yaml`, 2026-10-20).

### The EHR's sites

`50-locumview-ehr-sites.json` blocks every address (`URLBlocklist` `*`) except those in `URLAllowlist`. As shipped it allows only the local "No EHR is set up" page and `chrome://policy`, so an administrator can see the policies in effect (it shows them; it cannot change them). To set up an EHR:

1. `EHR_URL` in `/etc/locumview/ehr.conf`: the address the EHR launcher opens.
2. The EHR's sites in `URLAllowlist`, including its sign-in pages (for example the identity provider's), in Chrome's URL filter format (`https://ehr.example.org`, `https://*.example.org`).


### Updates

Chrome's own updater cannot run (`/opt/google/chrome` is part of the read-only image), and `/etc/default/google-chrome` stops its daily cron job from adding Google's repository back. Chrome is updated by rebuilding the image, which CI does on each change; to stay on a supported version (a manual STIG check), the image is rebuilt at least as often as Chrome's release cycle, every four weeks plus security releases.

## Firefox ESR

`/etc/firefox/policies/policies.json` follows the DISA Mozilla Firefox STIG V6R8 (2026-05-08, 33 findings), set through Firefox's enterprise policies:

| Finding | Requirement | Policy |
|---|---|---|
| V-251545 | Supported version | Red Hat's Flatpak, updated with the desktop's Flatpaks |
| V-251546 | TLS 1.2 or higher | `SSLVersionMin` tls1.2 |
| V-251547 | Ask for the client certificate | `Preferences` `security.default_personal_cert` "Ask Every Time" |
| V-251548 | No automatic search plugin updates | `Preferences` `browser.search.update` false |
| V-251549 | No automatic add-on updates | `ExtensionUpdate` false |
| V-251550 | Unauthorized MIME types not run or downloaded automatically | Firefox's default (asks); not set by policy yet |
| V-251551 | No form fill | `DisableFormHistory` |
| V-251552 | No password store | `PasswordManagerEnabled` false, `OfferToSaveLogins` false |
| V-251553 | Pop-ups blocked | `PopupBlocking` locked |
| V-251554, V-251555 | Scripts cannot move, resize, raise or lower windows | `Preferences` `dom.disable_window_move_resize`, `dom.disable_window_flip` |
| V-251557 | No extension installation | `ExtensionSettings` `*` blocked, `InstallAddonsPermission` |
| V-251558 | No background submission to Mozilla | `DisableTelemetry` |
| V-251560 | DoD root certificates | Not applicable outside the DoD; an organization adds its own CA with the `Certificates` policy |
| V-251562 | No quick data deletion | `DisableForgetButton` |
| V-251563 | No private browsing | `DisablePrivateBrowsing` |
| V-251564 | No search suggestions | `SearchSuggestEnabled` false |
| V-251566 | No network prediction | `NetworkPrediction` false |
| V-251567 to V-251569 | Fingerprinting, cryptomining and enhanced tracking protection | `EnableTrackingProtection` locked |
| V-251570, V-251572 | No extension recommendations | `UserMessaging`, `Preferences` `extensions.htmlaboutaddons.recommendations.enabled` |
| V-251571 | No deprecated ciphers | Firefox's default since version 93 (3DES off); Firefox does not let a policy set `security.ssl3.*` prefs |
| V-251573 | New Tab page content restricted | `FirefoxHome` locked |
| V-251577 | No DNS over HTTPS | `DNSOverHTTPS` locked off |
| V-251578 | No Firefox Accounts | `DisableFirefoxAccounts` |
| V-251580 | No feedback menus | `DisableFeedbackCommands` |
| V-251581 | No Encrypted Media Extensions | `EncryptedMediaExtensions` locked off |
| V-252881 | Data kept at shutdown | `SanitizeOnShutdown` all false, locked |
| V-252909 | No Firefox Studies | `DisableFirefoxStudies` |
| V-251559 | No developer tools | `DisableDeveloperTools` |
| V-251565 | No autoplay | `Permissions` `Autoplay` block-audio-video, locked |

Also: `DontCheckDefaultBrowser`, and location and notification requests blocked (Pocket is gone from Firefox 140, and so is its policy). `about:policies` shows the policies in effect; on lv-test14 (2026-10-20) every policy was active and none was rejected. Each name was checked against the policy list in this Firefox build (`Policies.sys.mjs`), and each pref against its allowlist.

**How the Flatpak sees it.** Red Hat's Firefox Flatpak cannot see the host's `/etc`; it reads policies from its `org.mozilla.firefox.systemconfig` extension, mounted at `/app/etc/firefox`. The image provides that extension as a link to `/etc/firefox` (`/usr/lib/tmpfiles.d/locumview-firefox.conf`), so `/etc/firefox/policies/policies.json` is what Firefox reads.
