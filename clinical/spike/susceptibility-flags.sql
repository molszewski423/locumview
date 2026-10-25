-- Phase 9 lite M1 spike, variant B: add the CLSI susceptibility interpretations to OpenEMR's lab-result flag list
-- (Administration > Lists > Procedure Result Abnormal), with the HL7 v3 ObservationInterpretation codes S, I, R and
-- SDD in the codes column. The HL7 importer stores OBX-8 S, I, R or SDD as the flag; FHIR then reads the code.
INSERT INTO list_options (list_id, option_id, title, seq, codes, activity) VALUES
  ('proc_res_abnormal', 'S', 'Susceptible', 100, 'S', 1),
  ('proc_res_abnormal', 'I', 'Intermediate', 110, 'I', 1),
  ('proc_res_abnormal', 'R', 'Resistant', 120, 'R', 1),
  ('proc_res_abnormal', 'SDD', 'Susceptible-dose dependent', 130, 'SDD', 1);
