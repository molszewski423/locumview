"""The SMART scopes the gateway requests, and registers with the EHR (e2e/setup.py). No dependencies, so the
registration helper can import it without the gateway's packages."""
SCOPES = ("openid fhirUser launch user/Patient.read user/Encounter.read user/Condition.read "
          "user/AllergyIntolerance.read user/MedicationRequest.read user/Observation.read user/DiagnosticReport.read "
          "user/Specimen.rs user/ServiceRequest.rs")
