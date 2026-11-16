"""Finding explanations by the local model (Phase 9 lite M4, ADR 0017: rules decide, the model only explains).

The model sees one finding at a time: its type, drug, summary, the data the rule used and the titles of its
references. Never the chart. Its reply is shown only if it passes a guard: every number it writes and every
antimicrobial it names must already be in the finding, so an explanation cannot carry a value, drug or dose the rule
did not see. A reply that fails is withheld, never repaired. The model, its digest, the prompt and the generation
options are pinned in model.json; the server's copy of the model must match the pinned digest. Standard library only.

Explanations are kept in memory (changelog #193, owner request): the same finding, word for word as the model would see
it, with the same model, prompt and options, is explained once and served from memory afterwards, so reopening a
patient does not run the model again. Any change to the finding (its data, summary or references, a new knowledge
base) or to the model, prompt or options makes a new key. Only "ok" and "withheld" results are kept; "unavailable" is
tried again. The memory is bounded (oldest first out) and is lost when the service restarts.
"""
from __future__ import annotations

import hashlib
import json
import re
from collections import OrderedDict
import urllib.error
import urllib.request
from pathlib import Path
from typing import Callable

DEFAULT_MODEL_FILE = Path(__file__).resolve().parent / "model.json"
MAX_CHARS = 1200        # two to four sentences; anything longer is not what the prompt asked for
TIMEOUT = 60            # seconds per model request; the first one may load the model (about 18 s measured)
CACHE_SIZE = 2000       # explanations kept in memory; a patient has a handful of findings

NUMBER = re.compile(r"\d+(?:\.\d+)?")
# Antimicrobial names by their usual stems, so a drug the knowledge base does not list is still caught.
ANTIMICROBIAL = re.compile(
    r"\b[a-z-]*(?:cillin|cef[a-z]+|ceph[a-z]+|penem|bactam|floxacin|mycin|micin|cycline|nidazole|conazole|fungin"
    r"|zolid|oxazole|prim|planin|vancin|colistin|polymyxin|aztreonam|fosfomycin|nitrofurantoin|rifampin|rifampicin"
    r"|clindamycin|daptomycin|tigecycline)s?\b")
# Classes are not drugs: "a third-generation cephalosporin" adds no agent the rule did not see.
CLASSES = {"cephalosporin", "cephalosporins", "carbapenem", "carbapenems", "penicillins", "fluoroquinolone",
           "fluoroquinolones", "aminoglycoside", "aminoglycosides", "beta-lactam", "beta-lactams", "macrolides"}


class ModelUnavailable(Exception):
    """The model cannot be used for this request; the message is safe to show (no chart content)."""


def _call(method: str, url: str, body: dict | None = None) -> dict:
    data = json.dumps(body).encode() if body is not None else None
    request = urllib.request.Request(url, data=data, method=method, headers={"Content-Type": "application/json"})
    with urllib.request.urlopen(request, timeout=TIMEOUT) as reply:     # noqa: S310 (an http URL from settings)
        return json.loads(reply.read())


class Explainer:
    def __init__(self, base_url: str, model_file: Path = DEFAULT_MODEL_FILE,
                 call: Callable[[str, str, dict | None], dict] = _call):
        config = json.loads(model_file.read_text())
        if not re.fullmatch(r"sha256:[0-9a-f]{64}", config["digest"]):
            raise ValueError(f"{model_file}: digest must be the model's sha256:<64 hex characters>")
        self.base_url = base_url.rstrip("/")
        self.name, self.digest, self.options = config["name"], config["digest"], config["options"]
        self.prompt_file = config["prompt"]
        self.prompt = (model_file.parent / self.prompt_file).read_text()
        self.call = call
        self.cache: OrderedDict[str, dict] = OrderedDict()

    def key(self, finding: dict) -> str:
        """Everything the model's answer and the guard's verdict depend on."""
        return hashlib.sha256(json.dumps([self.name, self.digest, self.prompt, self.options, message(finding),
                                          finding["evidence"], finding["summary"]], sort_keys=True).encode()).hexdigest()

    def cached(self, finding: dict) -> dict | None:
        result = self.cache.get(self.key(finding))
        return None if result is None else dict(result, cached=True)

    def describe(self) -> dict:
        return {"name": self.name, "digest": self.digest, "prompt": self.prompt_file}

    def check_model(self) -> None:
        """The server must hold the pinned model, by digest (a changed model is a different evaluation build)."""
        try:
            models = self.call("GET", f"{self.base_url}/api/tags", None).get("models", [])
        except (urllib.error.URLError, OSError, ValueError):
            raise ModelUnavailable("The model server could not be reached") from None
        found = next((m for m in models if m.get("name") == self.name or m.get("model") == self.name), None)
        if found is None:
            raise ModelUnavailable(f"The model server does not have {self.name}")
        if f"sha256:{found.get('digest')}" != self.digest:      # Ollama reports the bare hex
            raise ModelUnavailable(f"The model server's {self.name} is not the pinned version")

    def explain(self, finding: dict) -> dict:
        """{"status": "ok", "text"} or {"status": "withheld" | "unavailable", "reason"}, with "cached" when it came
        from memory."""
        hit = self.cached(finding)
        if hit is not None:
            self.cache.move_to_end(self.key(finding))
            return hit
        result = self._explain(finding)
        if result["status"] in ("ok", "withheld"):
            self.cache[self.key(finding)] = result
            while len(self.cache) > CACHE_SIZE:
                self.cache.popitem(last=False)
        return dict(result, cached=False)

    def _explain(self, finding: dict) -> dict:
        try:
            reply = self.call("POST", f"{self.base_url}/api/chat", {
                "model": self.name, "stream": False, "think": False, "options": self.options,
                "messages": [{"role": "system", "content": self.prompt},
                             {"role": "user", "content": message(finding)}]})
            text = reply["message"]["content"].strip()
        except (urllib.error.URLError, OSError, ValueError, KeyError, TypeError):
            return {"status": "unavailable", "reason": "The model did not answer"}
        problem = check(text, finding)
        if problem:
            return {"status": "withheld", "reason": problem}
        return {"status": "ok", "text": text}


def message(finding: dict) -> str:
    """The only thing the model is told: the finding as the rule produced it."""
    lines = [f"Finding: {finding['type']} ({finding['module']})", f"Drug: {finding['drug']}",
             f"Rule's summary: {finding['summary']}", "Data the rule used:"]
    lines += [f"- {e}" for e in finding["evidence"]]
    lines += ["References:"] + [f"- {c['title']}" for c in finding["citations"]]
    return "\n".join(lines)


def check(text: str, finding: dict) -> str | None:
    """Why the explanation may not be shown, or None. It may only restate what the finding holds."""
    if not text:
        return "The model returned nothing"
    if len(text) > MAX_CHARS:
        return "The explanation was longer than allowed"
    source = message(finding).lower()
    numbers = set(NUMBER.findall(source))
    extra = sorted({n for n in NUMBER.findall(text) if n not in numbers})
    if extra:
        return f"It gave numbers the finding does not contain: {', '.join(extra)}"
    drugs = sorted({d for d in ANTIMICROBIAL.findall(text.lower()) if d not in CLASSES and d not in source})
    if drugs:
        return f"It named antimicrobials the finding does not contain: {', '.join(drugs)}"
    return None
