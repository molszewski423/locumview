// Findings for the launched patient: the gateway reads the chart and asks the agent service (clinical/agent), whose
// deterministic rules decide every finding (ADR 0017). The app only shows them, with the data and the references each
// one rests on.
export interface Citation {
  ref: string;
  title: string;
  source?: string | null;
  pmid?: string | null;
  doi?: string | null;
}

export interface Finding {
  rule: string;
  module: string;
  type: string;
  drug: string;
  summary: string;
  evidence: string[];
  citations: Citation[];
}

export interface FindingsReply {
  knowledge_version: string;
  as_of: string;
  modules: string[];
  findings: Finding[];
}

export type FindingsState =
  | { status: "loading" }
  | { status: "ready"; reply: FindingsReply }
  | { status: "unavailable"; message: string };

export const TYPE_LABELS: Record<string, string> = {
  "bug-drug-mismatch": "Bug-drug mismatch",
  "suboptimal-agent": "Suboptimal agent",
  "missing-empiric-coverage": "Missing empiric coverage",
  "de-escalation": "De-escalation",
  "iv-to-po-switch": "IV to PO switch",
  "redundant-coverage": "Redundant coverage",
  "duration-review": "Duration review",
};

export function typeLabel(type: string): string {
  return TYPE_LABELS[type] ?? type;
}

export function forModule(state: FindingsState, module: string): Finding[] {
  return state.status === "ready" ? state.reply.findings.filter((f) => f.module === module) : [];
}

export function citationLink(c: Citation): string | undefined {
  if (c.pmid) return `https://pubmed.ncbi.nlm.nih.gov/${encodeURIComponent(c.pmid)}/`;
  if (c.doi) return `https://doi.org/${c.doi.split("/").map(encodeURIComponent).join("/")}`;
  return undefined;
}

export async function loadFindings(): Promise<FindingsState> {
  try {
    const response = await fetch("api/findings", { credentials: "same-origin", headers: { Accept: "application/json" } });
    if (!response.ok) {
      const detail = await response.json().then((b: { detail?: string }) => b.detail).catch(() => undefined);
      return { status: "unavailable", message: detail ?? `HTTP ${response.status}` };
    }
    return { status: "ready", reply: (await response.json()) as FindingsReply };
  } catch {
    return { status: "unavailable", message: "The findings service could not be reached" };
  }
}
