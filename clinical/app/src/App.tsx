import { useState } from "react";
import type { Chart } from "./smart";
import { age, labs, latestVitals, patientName, patientNumber, route, text, value, when } from "./fhir/chart";
import { cultures, formatMic, INTERPRETATIONS } from "./fhir/micro";

const MODULES = [
  { id: "stewardship", name: "Antimicrobial Stewardship" },
  { id: "iv-to-po", name: "IV to PO" },
  { id: "ade", name: "ADE Monitoring" },
] as const;
type View = "home" | "patient" | (typeof MODULES)[number]["id"];

export function App({ chart }: { chart: Chart }) {
  const [view, setView] = useState<View>("patient");
  const p = chart.patient;
  return (
    <div className="shell">
      <header className="bar">
        <span className="brand">LocumView Clinical</span>
        <span className="context" aria-label="Patient in context">
          {patientName(p)} · {age(p.birthDate) ?? "?"} y · {p.gender ?? ""} {patientNumber(p) ? `· ${patientNumber(p)}` : ""}
        </span>
        <span className="badge">Read-only · synthetic data</span>
      </header>
      <nav className="tabs">
        <button aria-current={view === "home"} onClick={() => setView("home")}>Home</button>
        {MODULES.map((m) => (
          <button key={m.id} aria-current={view === m.id} onClick={() => setView(m.id)}>{m.name}</button>
        ))}
        <button aria-current={view === "patient"} onClick={() => setView("patient")}>Patient</button>
      </nav>
      <main>
        {view === "home" && <Home />}
        {MODULES.map((m) => view === m.id && <Queue key={m.id} name={m.name} />)}
        {view === "patient" && <PatientView chart={chart} />}
      </main>
    </div>
  );
}

function Home() {
  return (
    <section>
      <h1>Triage</h1>
      <div className="cards">
        {MODULES.map((m) => (
          <div className="card" key={m.id}><div className="count">0</div><div>{m.name}</div></div>
        ))}
      </div>
      <p className="note">No findings yet: the rules service arrives in milestone M4. Every finding will show the data and
        guideline it rests on, and a local model's explanation of it.</p>
    </section>
  );
}

function Queue({ name }: { name: string }) {
  return (
    <section>
      <h1>{name}</h1>
      <p className="empty">The queue is empty. Findings appear here once the rules service is built (M4).</p>
    </section>
  );
}

function PatientView({ chart }: { chart: Chart }) {
  const vitals = latestVitals(chart.observations);
  const results = labs(chart.observations);
  const micro = cultures(chart.observations, chart.specimens);
  const active = chart.medications.filter((m) => m.status === "active");
  return (
    <section className="patient">
      <div className="grid">
        <Panel title="Problems">
          <List items={chart.conditions.map((c) => text(c.code))} empty="No problems recorded" />
        </Panel>
        <Panel title="Allergies">
          <List items={chart.allergies.map((a) => text(a.code))} empty="No known allergies recorded" />
        </Panel>
        <Panel title="Active medications">
          <table><tbody>
            {active.map((m) => (
              <tr key={m.id}><td>{text(m.medicationCodeableConcept)}</td><td>{route(m)}</td><td>{m.dosageInstruction?.[0]?.text}</td></tr>
            ))}
          </tbody></table>
          {active.length === 0 && <p className="empty">None</p>}
        </Panel>
        <Panel title="Latest vital signs">
          <table><tbody>
            {vitals.map((v) => <tr key={v.name}><td>{v.name}</td><td>{v.value}</td><td className="when">{when(v.when)}</td></tr>)}
          </tbody></table>
          {vitals.length === 0 && <p className="empty">None</p>}
        </Panel>
      </div>
      <Panel title="Microbiology">
        {micro.length === 0 && <p className="empty">No resulted cultures</p>}
        {micro.map((c, i) => (
          <div className="culture" key={i}>
            <h3>{c.organism?.name} <span className="meta">{c.specimen} · collected {when(c.collected)} · resulted {when(c.resulted)}</span></h3>
            <table>
              <thead><tr><th>Antibiotic</th><th>MIC</th><th>Interpretation</th></tr></thead>
              <tbody>
                {c.susceptibilities.map((s) => (
                  <tr key={s.drug} className={`interp-${s.interpretation ?? "none"}`}>
                    <td>{s.drug}</td><td>{formatMic(s.mic)}</td>
                    <td>{s.interpretation ? `${s.interpretation} · ${INTERPRETATIONS[s.interpretation]}` : ""}</td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        ))}
      </Panel>
      <Panel title="Laboratory results">
        <table><tbody>
          {results.map((o) => <tr key={o.id}><td>{text(o.code)}</td><td>{value(o)}</td><td className="when">{when(o.effectiveDateTime)}</td></tr>)}
        </tbody></table>
        {results.length === 0 && <p className="empty">None</p>}
      </Panel>
    </section>
  );
}

function Panel({ title, children }: { title: string; children: React.ReactNode }) {
  return <div className="panel"><h2>{title}</h2>{children}</div>;
}

function List({ items, empty }: { items: string[]; empty: string }) {
  return items.length ? <ul>{items.map((x, i) => <li key={i}>{x}</li>)}</ul> : <p className="empty">{empty}</p>;
}
