-- Phase 9 lite M1 spike: turn on OpenEMR's REST and FHIR APIs on the disposable instance (configuration only; the
-- same settings an administrator changes under Administration > Config > Connectors).
-- The password grant is for the spike's scripted read-back only; M3 uses the SMART EHR launch.
UPDATE globals SET gl_value = '1' WHERE gl_name IN ('rest_api', 'rest_fhir_api');
UPDATE globals SET gl_value = '1' WHERE gl_name = 'oauth_password_grant';
UPDATE globals SET gl_value = 'https://127.0.0.1:18443' WHERE gl_name = 'site_addr_oath';
