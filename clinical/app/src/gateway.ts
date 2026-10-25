// The app reads the chart through its gateway (server/gateway.py), which completed the SMART EHR launch on the server
// and holds the tokens; the browser only sends its session cookie, to the same origin. Every read is a GET, pinned by
// the gateway to the patient the app was launched on.
import type { AllergyIntolerance, Bundle, Condition, Encounter, MedicationRequest, Observation, Patient, Resource, Specimen } from "./fhir/types";

async function get<T>(path: string): Promise<T> {
  const response = await fetch(path, { credentials: "same-origin", headers: { Accept: "application/json" } });
  if (!response.ok) {
    // The gateway explains refusals in {"detail": "..."}; show it rather than a generic message.
    const detail = await response.json().then((body: { detail?: string }) => body.detail).catch(() => undefined);
    throw new Error(detail ?? `The EHR could not be read (HTTP ${response.status})`);
  }
  return response.json();
}

async function search<T extends Resource>(type: string): Promise<T[]> {
  const bundle = await get<Bundle<T>>(`api/fhir/${type}`);
  return (bundle.entry ?? []).map((e) => e.resource);
}

export interface Chart {
  patient: Patient;
  encounters: Encounter[];
  conditions: Condition[];
  allergies: AllergyIntolerance[];
  medications: MedicationRequest[];
  observations: Observation[];
  specimens: Specimen[];
}

export async function loadChart(): Promise<Chart> {
  const [patient, encounters, conditions, allergies, medications, observations, specimens] = await Promise.all([
    get<Patient>("api/fhir/Patient"),
    search<Encounter>("Encounter"),
    search<Condition>("Condition"),
    search<AllergyIntolerance>("AllergyIntolerance"),
    search<MedicationRequest>("MedicationRequest"),
    search<Observation>("Observation"),
    search<Specimen>("Specimen"),
  ]);
  return { patient, encounters, conditions, allergies, medications, observations, specimens };
}
