import { afterEach, describe, expect, it, vi } from "vitest";
import { citationLink, forModule, loadFindings, typeLabel, type FindingsReply } from "./findings";

const reply: FindingsReply = {
  knowledge_version: "0.1.0",
  as_of: "2026-10-22T09:40:00-04:00",
  modules: ["iv-to-po", "stewardship"],
  findings: [
    { rule: "bug-drug-mismatch", module: "stewardship", type: "bug-drug-mismatch", drug: "Ceftriaxone",
      summary: "s", evidence: ["e"], citations: [{ ref: "clsi-m100", title: "M100" }] },
    { rule: "iv-to-po-switch", module: "iv-to-po", type: "iv-to-po-switch", drug: "Levofloxacin",
      summary: "s", evidence: ["e"], citations: [] },
  ],
};

afterEach(() => vi.unstubAllGlobals());

describe("findings", () => {
  it("names every finding type the rules produce", () => {
    expect(typeLabel("iv-to-po-switch")).toBe("IV to PO switch");
    expect(typeLabel("something-new")).toBe("something-new");
  });

  it("filters by module only once findings are ready", () => {
    expect(forModule({ status: "ready", reply }, "iv-to-po").map((f) => f.drug)).toEqual(["Levofloxacin"]);
    expect(forModule({ status: "loading" }, "iv-to-po")).toEqual([]);
  });

  it("links a reference by PubMed id, else by DOI, else not at all", () => {
    expect(citationLink({ ref: "a", title: "t", pmid: "21292654", doi: "10.1/x" })).toBe("https://pubmed.ncbi.nlm.nih.gov/21292654/");
    expect(citationLink({ ref: "a", title: "t", doi: "10.1093/cid/ciq257" })).toBe("https://doi.org/10.1093/cid/ciq257");
    expect(citationLink({ ref: "a", title: "t" })).toBeUndefined();
  });

  it("reads the gateway's reply", async () => {
    vi.stubGlobal("fetch", vi.fn(async () => new Response(JSON.stringify(reply), { status: 200 })));
    expect(await loadFindings()).toEqual({ status: "ready", reply });
  });

  it("shows the gateway's reason when findings are unavailable", async () => {
    vi.stubGlobal("fetch", vi.fn(async () => new Response(JSON.stringify({ detail: "The findings service is not set up" }), { status: 503 })));
    expect(await loadFindings()).toEqual({ status: "unavailable", message: "The findings service is not set up" });
  });

  it("does not break the chart when the network fails", async () => {
    vi.stubGlobal("fetch", vi.fn(async () => { throw new TypeError("network"); }));
    expect((await loadFindings()).status).toBe("unavailable");
  });
});
