// The parts of FHIR R4 the app reads. Deliberately small: only fields the views use.
export interface Coding { system?: string; code?: string; display?: string }
export interface CodeableConcept { coding?: Coding[]; text?: string }
export interface Reference { reference?: string; display?: string }
export interface Quantity { value?: number; unit?: string; comparator?: string; system?: string; code?: string }

export interface Resource { resourceType: string; id?: string }
export interface Bundle<T extends Resource = Resource> extends Resource {
  entry?: { resource: T }[];
  link?: { relation: string; url: string }[];
}

export interface Patient extends Resource {
  name?: { use?: string; family?: string; given?: string[] }[];
  gender?: string;
  birthDate?: string;
  identifier?: { type?: CodeableConcept; value?: string }[];
}
export interface Condition extends Resource { code?: CodeableConcept; clinicalStatus?: CodeableConcept; onsetDateTime?: string }
export interface AllergyIntolerance extends Resource { code?: CodeableConcept; clinicalStatus?: CodeableConcept; text?: { div?: string } }
export interface Dosage { text?: string; route?: CodeableConcept }
export interface MedicationRequest extends Resource {
  status?: string;
  medicationCodeableConcept?: CodeableConcept;
  dosageInstruction?: Dosage[];
  authoredOn?: string;
}
export interface Observation extends Resource {
  status?: string;
  category?: CodeableConcept[];
  code: CodeableConcept;
  effectiveDateTime?: string;
  valueQuantity?: Quantity;
  valueString?: string;
  valueCodeableConcept?: CodeableConcept;
  interpretation?: CodeableConcept[];
  referenceRange?: { low?: Quantity; high?: Quantity; text?: string }[];
  specimen?: Reference;
  component?: { code: CodeableConcept; valueQuantity?: Quantity }[];
}
export interface Specimen extends Resource {
  type?: CodeableConcept;
  accessionIdentifier?: { value?: string };
  collection?: { collectedDateTime?: string };
}
export interface Encounter extends Resource { class?: Coding; period?: { start?: string; end?: string }; reasonCode?: CodeableConcept[] }
