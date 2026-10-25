// Display helpers for the patient view: names, ages, vitals and labs from FHIR as OpenEMR 8.4.1 returns it.
import type { CodeableConcept, MedicationRequest, Observation, Patient } from "./types";
import { isOrganism, isSusceptibility } from "./micro";

export function text(c?: CodeableConcept): string {
  return c?.text ?? c?.coding?.[0]?.display ?? c?.coding?.[0]?.code ?? "";
}

export function patientName(p: Patient): string {
  const n = p.name?.find((x) => x.use === "official") ?? p.name?.[0];
  return [n?.given?.join(" "), n?.family].filter(Boolean).join(" ") || "Unnamed patient";
}

export function patientNumber(p: Patient): string | undefined {
  return p.identifier?.find((i) => i.type?.coding?.some((c) => c.code === "PT"))?.value;
}

export function age(birthDate: string | undefined, on = new Date()): number | undefined {
  if (!birthDate) return undefined;
  const b = new Date(`${birthDate}T00:00:00Z`);
  let years = on.getUTCFullYear() - b.getUTCFullYear();
  if (on.getUTCMonth() < b.getUTCMonth() || (on.getUTCMonth() === b.getUTCMonth() && on.getUTCDate() < b.getUTCDate())) years--;
  return years;
}

export function when(iso?: string): string {
  if (!iso) return "";
  const d = new Date(iso);
  return Number.isNaN(d.getTime()) ? iso : d.toLocaleString(undefined, { dateStyle: "medium", timeStyle: "short" });
}

const VITALS: Record<string, string> = {
  "8310-5": "Temperature", "8867-4": "Heart rate", "9279-1": "Respiratory rate", "59408-5": "SpO2", "2708-6": "SpO2",
  "85354-9": "Blood pressure",
};

export function isVital(o: Observation): boolean {
  return o.category?.some((c) => c.coding?.some((x) => x.code === "vital-signs")) ?? false;
}

/** Latest reading of each vital sign that has a value (OpenEMR also returns empty vitals). */
export function latestVitals(observations: Observation[]): { name: string; value: string; when?: string }[] {
  const latest = new Map<string, { name: string; value: string; when?: string }>();
  const sorted = observations.filter(isVital).sort((a, b) => (a.effectiveDateTime ?? "").localeCompare(b.effectiveDateTime ?? ""));
  for (const o of sorted) {
    const c = o.code.coding?.find((x) => x.code && x.code in VITALS)?.code;
    if (!c) continue;
    let value: string | undefined;
    if (c === "85354-9") {
      const part = (code: string) => o.component?.find((x) => x.code.coding?.some((y) => y.code === code))?.valueQuantity?.value;
      const s = part("8480-6"), d = part("8462-4");
      value = s && d ? `${s}/${d} mmHg` : undefined;
    } else if (o.valueQuantity?.value) {
      value = `${o.valueQuantity.value} ${o.valueQuantity.unit ?? ""}`.trim();
    }
    if (value) latest.set(VITALS[c], { name: VITALS[c], value, when: o.effectiveDateTime });
  }
  return [...latest.values()];
}

/** Laboratory results other than microbiology, newest first. */
export function labs(observations: Observation[]): Observation[] {
  return observations
    .filter((o) => o.category?.some((c) => c.coding?.some((x) => x.code === "laboratory")) && !isOrganism(o) && !isSusceptibility(o))
    .sort((a, b) => (b.effectiveDateTime ?? "").localeCompare(a.effectiveDateTime ?? ""));
}

export function value(o: Observation): string {
  if (o.valueQuantity?.value !== undefined) return `${o.valueQuantity.comparator ?? ""}${o.valueQuantity.value} ${o.valueQuantity.unit ?? ""}`.trim();
  return o.valueString ?? text(o.valueCodeableConcept);
}

export function route(m: MedicationRequest): string {
  return text(m.dosageInstruction?.[0]?.route);
}
