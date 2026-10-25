// Phase 9 lite M3: SMART EHR launch, end to end, in a real browser (Playwright's Chromium).
// A clinician signs in to the local OpenEMR, opens a case patient's chart, launches the app from the chart's
// "SMART Enabled Apps" card, approves OpenEMR's authorization screens, and the app must open on that patient.
// Run by clinical/app/e2e.sh; credentials arrive as environment variables from the run's tmpfs state.
import { chromium } from "playwright-core";
import { mkdirSync } from "node:fs";

const EMR = "https://127.0.0.1:18443";
const { OE_USER, OE_PASS, PID, APP_NAME, APP_URL, EXPECT_NAME, EXPECT_ORGANISM, OUT = "/out" } = process.env;
mkdirSync(OUT, { recursive: true });
const browser = await chromium.launch();
const context = await browser.newContext({ ignoreHTTPSErrors: true, viewport: { width: 1280, height: 900 } });
const page = await context.newPage();
// Report requests that fail or are refused, with their CORS headers: browser apps fail on these first.
const failures = [];
page.on("requestfailed", (r) => failures.push(`${r.method()} ${r.url().split("?")[0]} failed: ${r.failure()?.errorText}`));
page.on("response", (r) => {
  if (r.status() >= 400 && r.url().startsWith(EMR)) {
    failures.push(`${r.request().method()} ${r.url().split("?")[0]} -> ${r.status()} acao=${r.headers()["access-control-allow-origin"] ?? "none"}`);
  }
});
let step = 0;
const shot = async (p, name) => p.screenshot({ path: `${OUT}/${String(++step).padStart(2, "0")}-${name}.png`, fullPage: true });

await page.goto(`${EMR}/interface/login/login.php?site=default`);
await page.fill("input[name=authUser]", OE_USER);
await page.fill("input[name=clearPass]", OE_PASS);
await Promise.all([page.waitForLoadState("networkidle"), page.click("#login-button")]);
await page.goto(`${EMR}/interface/patient_file/summary/demographics.php?set_pid=${PID}`);
await page.waitForLoadState("networkidle");
await shot(page, "chart");

// The chart's "SMART Enabled Apps" card starts collapsed; expand it, then launch this app by its registered name.
const launchButton = page.locator(`.smart-launch-btn[data-smart-name="${APP_NAME}"]`);
if (!(await launchButton.isVisible())) await page.getByText("SMART Enabled Apps", { exact: true }).click();
await launchButton.waitFor({ state: "visible", timeout: 10000 });
await shot(page, "smart-apps");
// OpenEMR opens the app in a full-height modal dialog with an iframe (library/js/utility.js, dlgopen 'modal-full').
await launchButton.click();
// APP_URL is where the app is served: OpenEMR's own origin (/clinical-app/), since OpenEMR 8.4.1's FHIR API does
// not answer CORS preflight requests and a cross-origin browser app cannot read it.
const appFrame = () => page.frames().find((f) => f !== page.mainFrame() && (f.url().startsWith(APP_URL) || /\/oauth2\//.test(f.url())));
// The dialog is laid out off-screen when the chart page is opened on its own, so forms are submitted directly
// through the button a user would press.
const submit = (f, selector) => f.evaluate((sel) => { const b = document.querySelector(sel); b.form.requestSubmit(b); }, selector);
const atApp = (f) => (f?.url() ?? "").startsWith(`${APP_URL}index.html`);

// OpenEMR's authorization flow inside that frame: possibly a login, then a consent screen listing the scopes.
// Approve until the frame reaches the app's index.html.
for (let i = 0; i < 20 && !atApp(appFrame()); i++) {
  const f = appFrame();
  if (!f) { await page.waitForTimeout(1000); continue; }
  await f.waitForLoadState("networkidle").catch(() => {});
  if (atApp(f)) break;
  await shot(page, `auth-${i}`);
  if (await f.locator("input[name=username]").count()) {
    // OpenEMR's OAuth sign-in offers a clinician login (user_role=api) and a patient login (portal-api).
    await f.fill("input[name=username]", OE_USER);
    await f.fill("input[name=password]", OE_PASS);
    await submit(f, "button[name=user_role][value=api]");
  } else if (await f.locator("#authorize-btn").count()) {
    // The consent screen: the app's read-only resource permissions, then Authorize.
    await submit(f, "#authorize-btn");
  }
  await page.waitForTimeout(1500);
}
const app = appFrame();
if (!app) throw new Error(`the app frame never appeared; frames: ${page.frames().map((f) => f.url()).join(", ")}`);
await app.waitForSelector(".context, .status.error", { timeout: 30000 });
await page.waitForTimeout(800);
await shot(page, "app");
const context_ = await app.locator(".context").textContent().catch(() => null);
const error = await app.locator(".status.error").textContent().catch(() => null);
const organisms = await app.locator(".culture h3").allTextContents().catch(() => []);
console.log(JSON.stringify({ url: app.url().split("?")[0], context: context_, error, organisms, failures }));
await browser.close();
const ok = context_?.includes(EXPECT_NAME) && organisms.some((o) => o.includes(EXPECT_ORGANISM));
process.exit(ok ? 0 : 1);
