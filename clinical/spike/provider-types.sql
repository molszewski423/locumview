-- Pharmacist provider types for OpenEMR's Provider Type list (physician_type), which ships with physician types only.
-- SNOMED CT occupations checked on tx.fhir.org, 2026-11-12. Idempotent. Owner request, 2026-11-12.
INSERT IGNORE INTO list_options (list_id, option_id, title, seq, codes, activity) VALUES
  ('physician_type', 'pharmacist', 'Pharmacist', 160, 'SNOMED-CT:46255001', 1),
  ('physician_type', 'clinical_pharmacist', 'Clinical pharmacist', 170, 'SNOMED-CT:734293001', 1);
