import { StrictMode } from "react";
import { createRoot } from "react-dom/client";
import { App } from "./App";
import { loadChart } from "./smart";
import "./styles.css";

const root = createRoot(document.getElementById("root")!);
root.render(<p className="status">Loading the patient's chart…</p>);
loadChart()
  .then((chart) => root.render(<StrictMode><App chart={chart} /></StrictMode>))
  .catch((error: Error) => root.render(
    <div className="status error"><h1>The clinical app could not open</h1><p>{error.message}</p>
      <p>Open it from a patient's chart in the EHR.</p></div>));
