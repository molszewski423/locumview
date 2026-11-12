"""The explanation step's contract: the model sees only the finding, a pinned model by digest, and a guard that withholds
any explanation carrying a number or an antimicrobial the finding does not hold. Standard library only, so it runs in
pre-commit:  python3 clinical/agent/test_explain.py"""
import json
import tempfile
import unittest
from pathlib import Path

from explain import DEFAULT_MODEL_FILE, Explainer, ModelUnavailable, check, message
from lvrules import Knowledge, evaluate, from_case

HERE = Path(__file__).resolve().parent
CITATIONS = json.loads((HERE.parent / "scenarios" / "citations.json").read_text())["citations"]
DIGEST = "ab" * 32


def as_dict(f):
    return {"rule": f.rule, "module": f.module, "type": f.type, "drug": f.drug, "summary": f.summary,
            "evidence": list(f.evidence),
            "citations": [{"ref": r, "title": CITATIONS.get(r, {}).get("title", r)} for r in f.refs]}


def every_finding():
    kb = Knowledge.load()
    for path in sorted((HERE.parent / "scenarios" / "cases").glob("*.json")):
        case = json.loads(path.read_text())
        for f in evaluate(from_case(case, kb), kb, set(case["modules"])):
            yield case["id"], as_dict(f)


class FakeOllama:
    def __init__(self, reply="", models=None, fail=False):
        self.reply, self.fail, self.requests = reply, fail, []
        self.models = [{"name": "gemma4:26b", "digest": DIGEST}] if models is None else models

    def __call__(self, method, url, body):
        self.requests.append((method, url, body))
        if self.fail:
            raise OSError("connection refused")
        if url.endswith("/api/tags"):
            return {"models": self.models}
        return {"message": {"role": "assistant", "content": self.reply}}


def explainer(fake, digest=f"sha256:{DIGEST}"):
    config = json.loads(DEFAULT_MODEL_FILE.read_text())
    config["digest"] = digest
    with tempfile.TemporaryDirectory() as tmp:
        model_file = Path(tmp) / "model.json"
        (Path(tmp) / "prompts").symlink_to(HERE / "prompts")
        model_file.write_text(json.dumps(config))
        return Explainer("http://ollama.test:11434/", model_file, call=fake)


class GuardTests(unittest.TestCase):
    def test_restating_any_real_finding_passes(self):
        for case, f in every_finding():
            with self.subTest(case=case, rule=f["rule"]):
                self.assertIsNone(check(f["summary"] + " " + " ".join(f["evidence"]), f))

    def test_a_number_the_finding_lacks_is_withheld(self):
        case, f = next(every_finding())
        self.assertIn("numbers", check(f"{f['summary']} Recheck in 72 hours.", f))

    def test_a_drug_the_finding_lacks_is_withheld_even_one_the_knowledge_base_does_not_list(self):
        case, f = next(every_finding())
        for drug in ("meropenem", "doxycycline", "Linezolid"):
            with self.subTest(drug=drug):
                self.assertIn("antimicrobials", check(f"{f['summary']} Consider {drug} instead.", f))

    def test_a_drug_class_is_not_a_drug(self):
        case, f = next(every_finding())
        self.assertIsNone(check(f"{f['summary']} This matters for cephalosporins and carbapenems.", f))

    def test_empty_or_overlong_replies_are_withheld(self):
        case, f = next(every_finding())
        self.assertIsNotNone(check("", f))
        self.assertIsNotNone(check("word " * 400, f))

    def test_the_model_is_told_the_finding_and_nothing_else(self):
        case, f = next(every_finding())
        text = message(f)
        self.assertIn(f["summary"], text)
        self.assertTrue(all(e in text for e in f["evidence"]))
        self.assertTrue(all(c["title"] in text for c in f["citations"]))


class ExplainerTests(unittest.TestCase):
    def setUp(self):
        self.case, self.finding = next(every_finding())

    def test_a_guarded_reply_is_returned_with_the_pinned_options(self):
        fake = FakeOllama(reply=self.finding["summary"])
        self.assertEqual(explainer(fake).explain(self.finding), {"status": "ok", "text": self.finding["summary"]})
        method, url, body = fake.requests[-1]
        self.assertEqual((method, url), ("POST", "http://ollama.test:11434/api/chat"))
        self.assertEqual((body["model"], body["stream"], body["think"]), ("gemma4:26b", False, False))
        self.assertEqual(body["options"], {"temperature": 0, "seed": 7, "num_predict": 400})
        self.assertEqual(body["messages"][0]["content"], (HERE / "prompts" / "explain-v2.txt").read_text())

    def test_an_unguarded_reply_is_withheld_not_repaired(self):
        reply = explainer(FakeOllama(reply="Switch to doxycycline 100 mg.")).explain(self.finding)
        self.assertEqual(reply["status"], "withheld")
        self.assertNotIn("text", reply)

    def test_an_unreachable_model_leaves_the_finding_unexplained(self):
        self.assertEqual(explainer(FakeOllama(fail=True)).explain(self.finding)["status"], "unavailable")
        with self.assertRaises(ModelUnavailable):
            explainer(FakeOllama(fail=True)).check_model()

    def test_the_server_must_hold_the_pinned_digest(self):
        explainer(FakeOllama()).check_model()
        with self.assertRaisesRegex(ModelUnavailable, "not the pinned version"):
            explainer(FakeOllama(models=[{"name": "gemma4:26b", "digest": "cd" * 32}])).check_model()
        with self.assertRaisesRegex(ModelUnavailable, "does not have"):
            explainer(FakeOllama(models=[])).check_model()

    def test_a_model_file_without_a_real_digest_is_refused(self):
        with self.assertRaises(ValueError):
            explainer(FakeOllama(), digest="MODEL_DIGEST")


if __name__ == "__main__":
    unittest.main()
