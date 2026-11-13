"""The versioned knowledge base the rules read (knowledge/antimicrobials.json)."""
from __future__ import annotations

import json
from pathlib import Path

DEFAULT = Path(__file__).resolve().parent.parent / "knowledge" / "antimicrobials.json"


class Knowledge:
    def __init__(self, data: dict):
        self.version = data["version"]
        self.agents = data["agents"]
        self.products = data["products"]
        self.tests = data["susceptibility_tests"]
        self.organisms = data["organisms"]
        self.specimens = data["specimens"]
        self.conditions = data["conditions"]
        self.thresholds = data["thresholds"]
        self.listeria_risk_factors = {k: v for k, v in data["listeria_risk_factors"].items() if not k.startswith("_")}
        self.rules = data["rules"]
        self.why = {k: v for k, v in data.get("why", {}).items() if not k.startswith("_")}

    @classmethod
    def load(cls, path: Path = DEFAULT) -> "Knowledge":
        return cls(json.loads(path.read_text()))

    def display(self, agent: str) -> str:
        return self.agents[agent]["display"]

    def has(self, agent: str, flag: str) -> bool:
        return bool(self.agents.get(agent, {}).get(flag))

    def susceptibility_agent(self, loinc: str) -> str | None:
        return self.tests.get(loinc, {}).get("agent")

    def organism_in(self, code: str | None, group: str) -> bool:
        return group in self.organisms.get(code or "", {}).get("groups", [])

    def condition_of(self, icd10: str | None) -> list[str]:
        if not icd10:
            return []
        return [name for name, c in self.conditions.items()
                if any(icd10.startswith(prefix) for prefix in c["icd10_prefixes"])]

    def listeria_risks(self, icd10: str | None) -> list[str]:
        """The Listeria risk-factor groups a problem code falls in (knowledge listeria_risk_factors)."""
        if not icd10:
            return []
        return [name for name, g in self.listeria_risk_factors.items()
                if any(icd10.startswith(prefix) for prefix in g["icd10_prefixes"])]
