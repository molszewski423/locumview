#!/usr/bin/env python3
"""AI-generated portraits for the synthetic patients (owner request, 2026-11-12). None shows a real person.

    portraits.py [--force] [SYN-001 LV-<case id> ...]     default: every patient without a photo yet

Runs on a workstation with an NVIDIA GPU, in a Python environment with torch (CUDA), diffusers, transformers,
accelerate and pillow; never in CI. The model is RealVisXL V5.0 (SG161222/RealVisXL_V5.0, CreativeML OpenRAIL++-M),
pinned by revision; set LOCUMVIEW_PORTRAIT_MODEL to the local path of RealVisXL_V5.0_fp16.safetensors at that
revision. Each portrait follows the patient's recorded age, sex, race and ethnicity (and, for a case, the
"portrait" text in clinical/scenarios/charts.json), with a seed derived from the patient number, so a photo can be made again. Output: a 512 x 640
JPEG per patient in this directory, named by patient number; the loader stores it as the patient's photograph.
"""
import hashlib
import json
import os
from datetime import date
from pathlib import Path
import sys

HERE = Path(__file__).resolve().parent
REVISION = "ac93e0dda1f6d448cae19bbfab8c5e720a5e48bc"  # pragma: allowlist secret (a public model revision)
TODAY = date(2026, 11, 12)   # ages as of the library's reference date
RACE = {"2106-3": "white", "2054-5": "Black", "2028-9": "Asian", "1002-5": "Native American",
        "2076-8": "Pacific Islander"}
STYLE = ("RAW photo, head and shoulders portrait for a hospital patient registration record, facing the camera, "
         "plain light gray background, soft even lighting, natural relaxed expression, everyday clothes, "
         "realistic skin texture, sharp focus, 85mm")
NEG = ("cartoon, illustration, painting, 3d render, anime, makeup, glamour, jewelry, earrings, text, watermark, "
       "logo, hospital gown, deformed, extra fingers, blurry, distorted face, asymmetrical eyes, oversaturated")


def age(birth):
    b = date.fromisoformat(birth)
    return TODAY.year - b.year - ((TODAY.month, TODAY.day) < (b.month, b.day))


def describe(sex, birth, race, ethnicity, extra=""):
    who = {"male": "man", "female": "woman"}[sex]
    if "2135-2" in ethnicity:
        people = "Hispanic"
    else:
        people = " and ".join(RACE[r] for r in race if r in RACE) or ""
    return ", ".join(x for x in (f"a {age(birth)}-year-old {people} {who}".replace("  ", " "), extra) if x)


def patients():
    for p in json.loads((HERE.parent / "synthea" / "background.json").read_text())["patients"]:
        d = p["demographics"]
        yield p["number"], describe(p["sex"], p["birth_date"], d["race"], d["ethnicity"])
    charts = json.loads((HERE.parent / "scenarios" / "charts.json").read_text())
    for path in sorted((HERE.parent / "scenarios" / "cases").glob("*.json")):
        c = json.loads(path.read_text())
        p, d = c["patient"], charts.get(c["id"], {}).get("demographics")
        if d:   # a case gets its photo once clinical/scenarios/charts.json has its demographics
            yield f"LV-{c['id']}", describe(p["sex"], p["birth_date"], d["race"], d["ethnicity"], d.get("portrait", ""))


def seed(number):
    return int(hashlib.sha256(number.encode()).hexdigest()[:8], 16)


def main(argv):
    force = "--force" in argv
    wanted = {a for a in argv if not a.startswith("--")}
    todo = [(n, text) for n, text in patients()
            if (not wanted or n in wanted) and (force or not (HERE / f"{n}.jpg").exists())]
    if not todo:
        print("every patient has a photo"); return
    import torch
    from diffusers import DPMSolverMultistepScheduler, StableDiffusionXLPipeline
    model = os.environ["LOCUMVIEW_PORTRAIT_MODEL"]
    assert REVISION in model, f"use RealVisXL V5.0 at revision {REVISION}"
    pipe = StableDiffusionXLPipeline.from_single_file(model, torch_dtype=torch.float16).to("cuda")
    pipe.scheduler = DPMSolverMultistepScheduler.from_config(pipe.scheduler.config, use_karras_sigmas=True)
    pipe.set_progress_bar_config(disable=True)
    for number, text in todo:
        image = pipe(prompt=f"{text}, {STYLE}", negative_prompt=NEG, num_inference_steps=30, guidance_scale=5.0,
                     width=832, height=1040, generator=torch.Generator("cuda").manual_seed(seed(number))).images[0]
        image.resize((512, 640)).save(HERE / f"{number}.jpg", quality=85, optimize=True)
        print(f"{number}: {text}")


if __name__ == "__main__":
    main(sys.argv[1:])
