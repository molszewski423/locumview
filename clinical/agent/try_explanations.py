#!/usr/bin/env python3
"""Every case's findings through the real model, to see what the guard shows and withholds (synthetic cases only).

    OLLAMA_URL=http://<ollama>:11434 python3 clinical/agent/try_explanations.py [case id ...]

Prints, per finding, the explanation's status and its text or the guard's reason, then a count. Exits non-zero if the
server's model is not the pinned one or any explanation was withheld or missing. Standard library only.
"""
import json
import os
import sys
from pathlib import Path

from explain import Explainer, ModelUnavailable
from lvrules import Knowledge, evaluate, from_case
from test_explain import as_dict

HERE = Path(__file__).resolve().parent


def main(ids: list[str]) -> int:
    explainer = Explainer(os.environ["OLLAMA_URL"])
    try:
        explainer.check_model()
    except ModelUnavailable as error:
        print(error, file=sys.stderr)
        return 2
    kb, counts = Knowledge.load(), {}
    for path in sorted((HERE.parent / "scenarios" / "cases").glob("*.json")):
        case = json.loads(path.read_text())
        if ids and case["id"] not in ids:
            continue
        for f in evaluate(from_case(case, kb), kb, set(case["modules"])):
            e = explainer.explain(as_dict(f))
            counts[e["status"]] = counts.get(e["status"], 0) + 1
            print(f"== {case['id']}: {f.type}, {f.drug}: {e['status']}\n{e.get('text') or e.get('reason')}\n")
    print(json.dumps(counts))
    return 0 if set(counts) <= {"ok"} else 1


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
