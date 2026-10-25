// Microbiology as OpenEMR 8.4.1 returns it through FHIR (M1 evidence, docs/evidence/clinical/20261025-openemr-m1-spike/):
// the organism is a valueString "<SNOMED CT code> (<name>)", MICs with a qualifier are strings ("<= 0.25"), exact MICs are
// valueQuantity, interpretations are coded S/I/R/SDD, and one sample appears as two Specimen resources with the same
// accession number (organism results reference one, susceptibilities the other). One organism per culture (owner's M1
// decision), so a culture's susceptibilities are those sharing its specimen accession.
import type { CodeableConcept, Observation, Reference, Specimen } from "./types";

export const INTERPRETATIONS = { S: "Susceptible", I: "Intermediate", R: "Resistant", SDD: "Susceptible-dose dependent", NS: "Non-susceptible" } as const;
export type Interpretation = keyof typeof INTERPRETATIONS;

export interface Organism { snomed?: string; name: string }
export interface Mic { comparator?: "<" | "<=" | ">=" | ">"; value: number; unit?: string }
export interface Susceptibility { drug: string; loinc?: string; mic?: Mic; interpretation?: Interpretation }
export interface Culture {
  test: string;            // what was cultured, e.g. "Bacteria identified in Urine by Culture"
  specimen?: string;       // specimen type, e.g. "Urine specimen"
  collected?: string;      // Specimen.collection.collectedDateTime
  resulted?: string;       // the organism result's effectiveDateTime
  accession?: string;
  organism?: Organism;
  susceptibilities: Susceptibility[];
}

const ORGANISM = /^\s*(\d+)\s+\((.+)\)\s*$/;
const QUALIFIED = /^\s*(<=|>=|<|>)?\s*(\d+(?:\.\d+)?)\s*$/;

/** "414102007 (Enterobacter cloacae complex)" -> code and name; anything else is kept as the name. */
export function parseOrganism(value: string): Organism {
  const m = ORGANISM.exec(value);
  return m ? { snomed: m[1], name: m[2] } : { name: value.trim() };
}

/** An MIC from valueQuantity or OpenEMR's text form ("<= 0.25", ">= 32", "16"). */
export function parseMic(o: Observation): Mic | undefined {
  if (o.valueQuantity?.value !== undefined) {
    return { value: o.valueQuantity.value, unit: o.valueQuantity.unit, comparator: o.valueQuantity.comparator as Mic["comparator"] };
  }
  const m = o.valueString === undefined ? null : QUALIFIED.exec(o.valueString);
  return m ? { comparator: (m[1] as Mic["comparator"]) || undefined, value: Number(m[2]) } : undefined;
}

export function formatMic(mic?: Mic): string {
  if (!mic) return "";
  return `${mic.comparator ?? ""}${mic.value}${mic.unit ? ` ${mic.unit}` : ""}`;
}

function code(concept?: CodeableConcept): string | undefined {
  return concept?.coding?.[0]?.code;
}

function display(concept?: CodeableConcept): string {
  return concept?.text ?? concept?.coding?.[0]?.display ?? "";
}

export function interpretation(o: Observation): Interpretation | undefined {
  const c = o.interpretation?.[0];
  const value = code(c) ?? c?.text;
  return value && value in INTERPRETATIONS ? (value as Interpretation) : undefined;
}

export function isSusceptibility(o: Observation): boolean {
  return display(o.code).includes("[Susceptibility]");
}

/** A culture's organism result: a culture test whose value is the organism text. */
export function isOrganism(o: Observation): boolean {
  return /by Culture$/.test(display(o.code)) && typeof o.valueString === "string";
}

function ref(r?: Reference): string | undefined {
  return r?.reference?.split("/").pop();
}

/** Drug name from the LOINC display, "Cefepime [Susceptibility] by Minimum inhibitory concentration (MIC)" -> "Cefepime". */
export function drugName(o: Observation): string {
  return display(o.code).split(" [Susceptibility]")[0].trim();
}

export function cultures(observations: Observation[], specimens: Specimen[]): Culture[] {
  const byId = new Map(specimens.map((s) => [s.id, s]));
  const accessionOf = (o: Observation) => {
    const s = byId.get(ref(o.specimen) ?? "");
    return s?.accessionIdentifier?.value ?? (s ? `specimen:${s.id}` : undefined);
  };
  const result: Culture[] = [];
  for (const o of observations.filter(isOrganism)) {
    const s = byId.get(ref(o.specimen) ?? "");
    const accession = accessionOf(o);
    result.push({
      test: display(o.code),
      specimen: display(s?.type),
      collected: s?.collection?.collectedDateTime,
      resulted: o.effectiveDateTime,
      accession,
      organism: parseOrganism(o.valueString ?? ""),
      susceptibilities: accession === undefined ? [] : observations
        .filter((x) => isSusceptibility(x) && accessionOf(x) === accession)
        .map((x) => ({ drug: drugName(x), loinc: code(x.code), mic: parseMic(x), interpretation: interpretation(x) }))
        .sort((a, b) => a.drug.localeCompare(b.drug)),
    });
  }
  return result.sort((a, b) => (b.resulted ?? "").localeCompare(a.resulted ?? ""));
}
