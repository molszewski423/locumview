"""The patient snapshot the rules read, and the adapter that builds it from a case file (locumview-case/1).

Rules never read a case file or FHIR directly: each source gets an adapter that produces this snapshot, so the tests
over the case library and the runtime over OpenEMR's FHIR API exercise the same rules. The FHIR adapter is the next
step of plan M4.
"""
from __future__ import annotations

from dataclasses import dataclass, field
from datetime import date, datetime

from .knowledge import Knowledge


@dataclass(frozen=True)
class Prescription:
    agent: str | None          # knowledge-base agent key; None for anything that is not an antimicrobial
    text: str
    route: str                 # IV, PO, IM, SC
    start: date
    end: date | None

    def active_on(self, day: date) -> bool:
        return self.start <= day and (self.end is None or self.end > day)


@dataclass(frozen=True)
class Susceptibility:
    loinc: str
    agent: str | None
    interpretation: str        # S, I, R, SDD, NS


@dataclass(frozen=True)
class Culture:
    specimen: str | None       # blood, urine, csf, or None when the specimen code is not known
    collected: datetime
    final: bool
    organism_code: str | None
    organism: str | None
    susceptibilities: tuple[Susceptibility, ...] = ()


@dataclass(frozen=True)
class Vital:
    taken: datetime
    temperature_f: float | None = None
    pulse: float | None = None
    respiration: float | None = None
    oxygen_saturation: float | None = None
    systolic: float | None = None


@dataclass(frozen=True)
class Problem:
    title: str
    icd10: str | None


@dataclass
class Snapshot:
    birth_date: date
    encounter_start: datetime
    problems: list[Problem] = field(default_factory=list)
    prescriptions: list[Prescription] = field(default_factory=list)
    vitals: list[Vital] = field(default_factory=list)
    cultures: list[Culture] = field(default_factory=list)
    as_of: datetime | None = None   # the newest charted time; rules judge "now" by it, never by the wall clock

    def age_on(self, day: date) -> int:
        b = self.birth_date
        return day.year - b.year - ((day.month, day.day) < (b.month, b.day))

    def active_antimicrobials(self) -> list[Prescription]:
        day = self.as_of.date()
        return [p for p in self.prescriptions if p.agent and p.active_on(day)]

    def final_isolates(self) -> list[Culture]:
        return [c for c in self.cultures if c.final and c.organism_code]


def _time(value: str) -> datetime:
    return datetime.fromisoformat(value)


def from_case(case: dict, kb: Knowledge) -> Snapshot:
    """Build a snapshot from a locumview-case/1 file: the chart data only, never the story or the expected answer."""
    times = [_time(case["encounter"]["start"])]
    problems = []
    for p in case.get("problems", []):
        code = p.get("diagnosis", "")
        problems.append(Problem(p["title"], code.removeprefix("ICD10:") if code.startswith("ICD10:") else None))
    prescriptions = [
        Prescription(kb.products.get(p["rxnorm"]), p["drug"], p["route"], date.fromisoformat(p["start"]),
                     date.fromisoformat(p["end"]) if p.get("end") else None)
        for p in case.get("prescriptions", [])]
    vitals = []
    for v in case.get("vitals", []):
        vitals.append(Vital(_time(v["taken"]), v.get("temperature_f"), v.get("pulse"), v.get("respiration"),
                            v.get("oxygen_saturation"), v.get("bps")))
        times.append(_time(v["taken"]))
    for lab in case.get("labs", []):
        times += [_time(lab[k]) for k in ("collected", "resulted") if k in lab]
    cultures = []
    for c in case.get("cultures", []):
        times += [_time(c[k]) for k in ("collected", "resulted") if k in c]
        organism = c.get("organism") or {}
        cultures.append(Culture(
            kb.specimens.get(c["specimen"]["snomed"]), _time(c["collected"]),
            c.get("status", "final") == "final", organism.get("snomed"), organism.get("text"),
            tuple(Susceptibility(s["loinc"], kb.susceptibility_agent(s["loinc"]), s["interpretation"])
                  for s in c.get("susceptibilities", []))))
    return Snapshot(date.fromisoformat(case["patient"]["birth_date"]), _time(case["encounter"]["start"]),
                    problems, prescriptions, vitals, cultures, max(times))
