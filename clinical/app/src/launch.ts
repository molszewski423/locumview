import { launch } from "./smart";

launch().catch((error: Error) => {
  document.body.textContent = `The SMART launch failed: ${error.message}`;
});
