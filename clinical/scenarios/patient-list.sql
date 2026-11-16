-- OpenEMR's patient list (Patient Finder) for the clinical demo, and the patient fields it shows (changelog #186).
-- Run by load.py on every load, after the patients are loaded; idempotent. Plain SQL, so it also runs on a database
-- restored from the demo baseline.

-- Birth sex in OpenEMR's list ids. FHIR patient creation stores the lower-case FHIR gender ("female"), which the
-- demographics form's list (Female, Male, UNK) does not match: the field showed Unassigned and, being required,
-- blocked every save of the form. The administrative "Sex" field, empty for synthetic patients, follows birth sex.
UPDATE patient_data SET sex = 'Female' WHERE BINARY sex = 'female';
UPDATE patient_data SET sex = 'Male' WHERE BINARY sex = 'male';
UPDATE patient_data SET sex_identified = sex
  WHERE (sex_identified IS NULL OR sex_identified = '') AND sex IN ('Female', 'Male');

-- Two list columns from the patient's encounters, kept in patient_data so the list sorts and searches them like its
-- own columns, without a change to OpenEMR's code: the chief complaint (the most recent encounter reason that is not
-- empty) and the date of the last visit. Refreshed on every load.
ALTER TABLE patient_data ADD COLUMN IF NOT EXISTS lv_chief_complaint VARCHAR(255) NOT NULL DEFAULT '';
ALTER TABLE patient_data ADD COLUMN IF NOT EXISTS lv_last_visit DATE NULL;
UPDATE patient_data p SET
  lv_chief_complaint = COALESCE((SELECT e.reason FROM form_encounter e WHERE e.pid = p.pid AND TRIM(e.reason) <> ''
                                 ORDER BY e.date DESC, e.id DESC LIMIT 1), ''),
  lv_last_visit = (SELECT DATE(MAX(e.date)) FROM form_encounter e WHERE e.pid = p.pid);

-- The list's columns (stock list "Patient List Columns"): name, sex, birth date, patient number, chief complaint,
-- last visit. The synthetic home phone and SSN are turned off.
UPDATE list_options SET activity = 0 WHERE list_id = 'ptlistcols' AND option_id IN ('phone_home', 'ss');
INSERT INTO list_options (list_id, option_id, title, seq, activity) VALUES
  ('ptlistcols', 'name', 'Full Name', 10, 1),
  ('ptlistcols', 'sex', 'Sex', 20, 1),
  ('ptlistcols', 'DOB', 'Date of Birth', 30, 1),
  ('ptlistcols', 'pubpid', 'External ID', 40, 1),
  ('ptlistcols', 'lv_chief_complaint', 'Chief Complaint', 50, 1),
  ('ptlistcols', 'lv_last_visit', 'Last Visit', 60, 1)
ON DUPLICATE KEY UPDATE title = VALUES(title), seq = VALUES(seq), activity = VALUES(activity);

-- 50 patients per page (stock default 10).
REPLACE INTO globals (gl_name, gl_index, gl_value) VALUES ('gbl_pt_list_page_size', 0, '50');
