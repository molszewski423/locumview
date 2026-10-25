// Tested against real OpenEMR 8.4.1 FHIR output: the M1 spike's normalized read-back (two fresh instances gave
// identical output), so a change in OpenEMR's formats fails here first.
import { readFileSync } from "node:fs";
import { describe, expect, it } from "vitest";
import { cultures, formatMic, parseMic, parseOrganism } from "./micro";
import type { Observation, Resource, Specimen } from "./types";

const evidence = new URL("../../../../docs/evidence/clinical/20261025-openemr-m1-spike/fhir-readback.normalized.json", import.meta.url);
const resources = JSON.parse(readFileSync(evidence, "utf8")) as Resource[];
const observations = resources.filter((r): r is Observation => r.resourceType === "Observation");
const specimens = resources.filter((r): r is Specimen => r.resourceType === "Specimen");

describe("organism text", () => {
  it("splits OpenEMR's '<SNOMED code> (<name>)' form", () => {
    expect(parseOrganism("414102007 (Enterobacter cloacae complex)")).toEqual({ snomed: "414102007", name: "Enterobacter cloacae complex" });
  });
  it("keeps text without a code as the name", () => {
    expect(parseOrganism("Mixed flora")).toEqual({ name: "Mixed flora" });
  });
});

describe("MIC", () => {
  const obs = (o: Partial<Observation>) => ({ resourceType: "Observation", code: {}, ...o }) as Observation;
  it("reads qualified text values", () => {
    expect(parseMic(obs({ valueString: ">= 32" }))).toEqual({ comparator: ">=", value: 32 });
    expect(parseMic(obs({ valueString: "<= 0.25" }))).toEqual({ comparator: "<=", value: 0.25 });
  });
  it("reads exact values from valueQuantity", () => {
    expect(parseMic(obs({ valueQuantity: { value: 4, unit: "ug/mL" } }))).toEqual({ value: 4, unit: "ug/mL", comparator: undefined });
  });
  it("returns nothing for text that is not an MIC", () => {
    expect(parseMic(obs({ valueString: "see comment" }))).toBeUndefined();
    expect(formatMic(undefined)).toBe("");
  });
});

describe("cultures from OpenEMR output", () => {
  const [culture, ...others] = cultures(observations, specimens);
  it("finds the one culture, with its organism, specimen and collection time", () => {
    expect(others).toHaveLength(0);
    expect(culture.organism).toEqual({ snomed: "112283007", name: "Escherichia coli" });
    expect(culture.specimen).toBe("Urine specimen");
    expect(culture.collected).toBe("2026-10-20T15:10:00+00:00");
    expect(culture.resulted).toBe("2026-10-22T09:40:00+00:00");
  });
  it("joins the susceptibilities by specimen accession across OpenEMR's two Specimen resources", () => {
    const refs = new Set(observations.map((o) => o.specimen?.reference).filter(Boolean));
    expect(refs.size).toBe(2); // the organism and the panel reference different Specimen resources
    expect(culture.susceptibilities).toHaveLength(11);
  });
  it("keeps each drug's MIC and coded interpretation", () => {
    const by = Object.fromEntries(culture.susceptibilities.map((s) => [s.drug, s]));
    expect(by["Ceftriaxone"]).toMatchObject({ interpretation: "R", mic: { comparator: ">=", value: 64 } });
    expect(by["Cefepime"]).toMatchObject({ interpretation: "SDD", mic: { value: 4, unit: "ug/mL" } });
    expect(by["Ampicillin+Sulbactam"]).toMatchObject({ interpretation: "I", mic: { value: 16 } });
    expect(by["Ertapenem"]).toMatchObject({ interpretation: "S", mic: { comparator: "<=", value: 0.25 } });
  });
});
