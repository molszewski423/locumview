# Patient photographs (AI-generated)

**Every face here is AI-generated. None shows a real person.** They give the synthetic patients a photograph in the
demo EHR (owner request, 2026-11-12), named by patient number: `SYN-nnn` for the Synthea background patients,
`LV-<case id>` for the scenario cases. The loader (`clinical/scenarios/load.py`) stores each as the patient's
photograph in OpenEMR, once.

- **Made with** `portraits.py`, locally on a workstation GPU (nothing sent to a cloud service), with RealVisXL V5.0
  (`SG161222/RealVisXL_V5.0`, revision `ac93e0dd`, CreativeML OpenRAIL++-M licence), 30 steps, 832 x 1040, saved as
  512 x 640 JPEG.
- **What a portrait follows:** the patient's recorded age (on 2026-11-12), sex, race and ethnicity, and for a case its
  `chart.demographics.portrait` text; the seed comes from the patient number, so `portraits.py --force <number>`
  makes the same photograph again with the same model and settings.
- **Reviewed by eye** before commit; a photograph that looks wrong is regenerated with an adjusted description.
