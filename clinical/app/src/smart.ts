// SMART on FHIR, EHR launch (SMART Health IT's fhirclient). The EHR opens launch.html with iss and launch; the
// client authorizes with PKCE and returns to index.html with the patient in context. Read-only: every scope is a read.
import { authorize, ready } from "fhirclient/browser";
import type { AllergyIntolerance, Bundle, Condition, Encounter, MedicationRequest, Observation, Patient, Resource, Specimen } from "./fhir/types";

export const SCOPES = [
  "launch", "openid", "fhirUser",
  "patient/Patient.read", "patient/Encounter.read", "patient/Condition.read", "patient/AllergyIntolerance.read",
  "patient/MedicationRequest.read", "patient/Observation.read", "patient/DiagnosticReport.read",
  "patient/Specimen.rs", "patient/ServiceRequest.rs",
].join(" ");

interface Config { clientId: string }

/** Deployment settings, read at run time so one build serves every site. */
async function config(): Promise<Config> {
  const response = await fetch("config.json", { cache: "no-store" });
  if (!response.ok) throw new Error("config.json is missing: the app is not set up for this site");
  return response.json();
}

export async function launch(): Promise<void> {
  const { clientId } = await config();
  await authorize({ clientId, scope: SCOPES, redirectUri: "index.html", pkceMode: "required" });
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
  const client = await ready();
  const id = client.patient.id;
  if (!id) throw new Error("No patient in context: open the app from a patient's chart in the EHR");
  // Every page of each search; OpenEMR pages at its own size.
  const all = async <T extends Resource>(query: string): Promise<T[]> => {
    const pages = (await client.request<Bundle<T> | Bundle<T>[]>(query, { pageLimit: 0 })) as Bundle<T> | Bundle<T>[];
    return (Array.isArray(pages) ? pages : [pages]).flatMap((b) => (b.entry ?? []).map((e) => e.resource));
  };
  const [patient, encounters, conditions, allergies, medications, observations, specimens] = await Promise.all([
    client.request<Patient>(`Patient/${id}`),
    all<Encounter>(`Encounter?patient=${id}`),
    all<Condition>(`Condition?patient=${id}`),
    all<AllergyIntolerance>(`AllergyIntolerance?patient=${id}`),
    all<MedicationRequest>(`MedicationRequest?patient=${id}`),
    all<Observation>(`Observation?patient=${id}`),
    all<Specimen>(`Specimen?patient=${id}`),
  ]);
  return { patient, encounters, conditions, allergies, medications, observations, specimens };
}
