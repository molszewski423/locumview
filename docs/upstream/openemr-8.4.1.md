# OpenEMR 8.4.1: defects found while building Phase 9 lite

Each was found against OpenEMR 8.4.1 (the pinned image) and checked in its source; where noted, the same code is on
OpenEMR's `master` branch as of 2026-10-25. Offering these upstream is the owner's decision (M1 decision, option 4:
contribute fixes in parallel). Nothing here has been submitted.

| # | Area | Defect | Effect on LocumView | Status here |
|---|---|---|---|---|
| 1 | SMART launch | `BearerTokenAuthorizationStrategy::populateTokenContextForRequest` passes `getRequestUserId()` (an `int`) to `checkUserHasAccessToPatient()`, which requires a UUID string. Same on `master`. | Every EHR launch with patient context fails the access check, for public and confidential clients | Patched locally: `clinical/spike/patches/0001-smart-launch-patient-access.diff` |
| 2 | SMART launch | `findPatientByUuid()` passes the UUID string to `getPidByUuid()`, which compares against the binary `uuid` column | With 1 fixed, the launched patient still never resolves | Same patch |
| 3 | CORS | The FHIR API answers a CORS preflight (`OPTIONS`) with `404`, although `CORSListener` is meant to answer it with `200` | A browser app on another origin cannot read FHIR with a token | Avoided: the app reads through its gateway, same origin |
| 4 | CORS | In `CORSListener::getInitialResponse`, `"Access-Control-Allow-Methods", "GET, ..."` uses a comma where `=>` is meant | The preflight response, when given, has no valid allowed-methods header | Avoided by the gateway |
| 5 | FHIR Observation | The HL7 importer's coded organism (CWE, SNOMED CT) is returned as `valueString` "`<code> (<name>)`" | Rules parse the text form; one organism per culture | Handled in the app's data layer; M1 evidence |
| 6 | FHIR Observation | Qualified MICs (SN, `>=^32`) are returned as text, not `valueQuantity` with `comparator` | Rules parse the text form | Handled in the app's data layer |
| 7 | FHIR Observation | A susceptibility result has no `derivedFrom`/`hasMember` link to its organism (OBR-26 is stored only as a report note) | No organism-to-susceptibility link beyond specimen accession | One organism per culture (owner decision) |
| 8 | FHIR DiagnosticReport | One DiagnosticReport per order, holding only one of the order's reports; `code` is "unknown" | Rules read Observations, not reports | Documented |
| 9 | FHIR Condition | The problem-list query reads `lists.diagnosis` without parsing it, so every problem returns text only | Problem codes unavailable to rules | Patched locally: `clinical/spike/patches/0002-problem-list-condition-codes.diff` parses the codes as `ConditionService` does and keeps the title as `code.text` |
| 10 | Registration | `token_endpoint_auth_method: none` is refused; public clients are registered by `application_type` other than `private` | Documentation gap | Documented |
| 11 | FHIR MedicationRequest | The prescription query does not select `start_date`, `authoredOn` comes only from `date_added` (empty for orders created through the REST API), and `status` is `completed` whenever `end_date` is set, even in the future | No start date for duration rules; a future stop date reads as stopped | Loader sets `date_added` to the start date; the adapter reads `authoredOn` and `status` |
| 12 | FHIR Specimen | `GET /fhir/Specimen` and `GET /fhir/Specimen/:uuid` require the superuser permission (`admin`/`super`) for a user token, while the lab order it belongs to (`ServiceRequest`) and other chart data need only `patients`/`med`. Not checked on `master` | A clinician who is not an administrator cannot read specimens; the app's chart fails with 403 (found 2026-11-11 with a non-admin pharmacist account) | Patched locally: `clinical/spike/patches/0003-specimen-chart-permission.diff` checks `patients`/`med`, as `ServiceRequest` does. `DiagnosticReport` has the same superuser check; neither the app nor the rules read it |

Evidence: M1 `docs/evidence/clinical/20261025-openemr-m1-spike/`, M2 changelog #75, M3
`docs/evidence/clinical/20261025-m3-local-launch/`.
