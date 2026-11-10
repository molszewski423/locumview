# LocumView clinical app (Phase 9 lite)

The clinical AI module's web app (ADR 0017): opened from a patient's chart in the EHR as a SMART on FHIR app, read-only,
on synthetic data. The patient view shows the patient's findings first (M4: decided by the agent service's
deterministic rules, each with the data and references it rests on), then problems, allergies, medications with
route, vital signs, laboratory results and microbiology with MICs and interpretations. Home and the module tabs show
the same patient's findings; a queue across patients needs its own access design and comes later.

```
browser (OpenEMR's dialog)  ->  gateway (server/)  ->  OpenEMR FHIR API
   the app, same origin          SMART launch, tokens,     read-only, the launched patient only
                                 session cookie
                                       |  /api/findings: the patient's chart, no token
                                       v
                                 agent service (clinical/agent/): rules -> findings
```

- `src/`: React and TypeScript. `src/fhir/micro.ts` turns OpenEMR's microbiology into cultures (tested against the
  M1 OpenEMR output); `src/gateway.ts` reads the chart through the gateway.
- `server/`: the gateway (FastAPI), its tests, and hash-pinned requirements. Why a gateway:
  `docs/evidence/clinical/20261025-m3-local-launch/`.
- `src/findings.ts`: reads `/api/findings`; a findings failure leaves the chart usable and says why.
- `e2e/` and `e2e.sh`: the end-to-end test: the launch, then exactly the case's expected findings on screen.

```fish
clinical/app/run.sh npm ci; and clinical/app/run.sh npm test; and clinical/app/run.sh npm run build
clinical/app/server/run.sh test
clinical/app/e2e.sh                       # fresh local OpenEMR, cases, agent, gateway, browser launch test, teardown
clinical/app/e2e.sh LV-uti-esbl-mismatch-01 --keep
```

Node tooling runs in a digest-pinned Node 22 container (`run.sh`), the gateway in the pinned Python 3.13 image CI uses
(`server/run.sh`); npm packages and Python wheels are releases older than two weeks at the time of pinning, and the
Python requirements are hash-pinned. CI runs both test suites and the build (`.gitea/workflows/checks.yml`).

Gateway settings are environment variables, documented at the top of `server/gateway.py`. The client secret is read
from a file (`CLIENT_SECRET_FILE`), never from the environment or the repository.
