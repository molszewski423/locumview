// Phase 9 lite M3 and M4: SMART EHR launch and the patient's findings, end to end, in a real browser (Playwright's Chromium).
// A clinician signs in to the local OpenEMR, opens a case patient's chart, launches the app from the chart's
// "SMART Enabled Apps" card, approves OpenEMR's authorization screens, and the app must open on that patient and show
// exactly the case's expected findings in the modules the case lists (from the agent service, through the gateway).
// Run by clinical/app/e2e.sh; credentials arrive as environment variables from the run's tmpfs state.
import { chromium } from "playwright-core";
import { mkdirSync } from "node:fs";

const EMR = "https://127.0.0.1:18443";
const { OE_USER, OE_PASS, PID, APP_NAME, APP_URL, EXPECT_NAME, EXPECT_ORGANISM, EXPECT_MODULES = "", EXPECT_FINDINGS = "", OUT = "/out" } = process.env;
mkdirSync(OUT, { recursive: true });
const browser = await chromium.launch();
// The site's time zone, as on a clinician's desktop: the agent writes its evidence in SITE_TZ, the browser shows the
// chart's times in its own zone, and the two agree only when they are the same.
const context = await browser.newContext({ ignoreHTTPSErrors: true, viewport: { width: 1280, height: 900 }, timezoneId: "America/New_York" });
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
// The test opens the chart page on its own rather than inside OpenEMR's tabbed main window, where dlgopen lays the
// dialog out; here the dialog is not shown, so fields are set and forms submitted directly, through the button a user
// would press. (Driving the tabbed main window instead is a known improvement.)
// A real click event, not form.requestSubmit(): OpenEMR's consent screen builds the granted scopes from its permission
// checkboxes in the Authorize button's click handler.
const submit = (f, selector) => f.evaluate((sel) => document.querySelector(sel).click(), selector);
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
    await f.evaluate(([user, pass]) => {
      document.querySelector("input[name=username]").value = user;
      document.querySelector("input[name=password]").value = pass;
    }, [OE_USER, OE_PASS]);
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
// The dialog's frame cannot be photographed here, so the same session opens the app in its own tab for the record.
const view = await context.newPage();
await view.goto(`${APP_URL}index.html`);
await view.waitForSelector(".context", { timeout: 20000 });
// Findings come from the agent service through the gateway (M4); wait until the rules have answered.
await view.waitForSelector(".finding, .patient .empty", { timeout: 20000 });
await view.waitForFunction(() => !document.body.textContent.includes("Checking the rules"), null, { timeout: 20000 });
await shot(view, "app");
await view.locator(".finding details").first().evaluate((d) => { d.open = true; }).catch(() => {});
await shot(view, "finding-detail");
const context_ = await app.locator(".context").textContent().catch(() => null);
const error = await app.locator(".status.error").textContent().catch(() => null);
const organisms = await app.locator(".culture h3").allTextContents().catch(() => []);
const granted = await app.evaluate(() => fetch("api/context").then((r) => r.json()).catch(() => null));
const modules = EXPECT_MODULES.split(",").filter(Boolean);
const findings = (await view.locator(".patient .finding").evaluateAll((els) =>
  els.map((e) => `${e.dataset.module}|${e.dataset.type}|${e.dataset.drug}`)))
  .filter((f) => modules.includes(f.split("|")[0])).sort();
const unavailable = await view.locator(".patient [role=status]").textContent().catch(() => null);
// Cookie names and attributes only (never values), to diagnose session problems.
const cookies = (await context.cookies(APP_URL)).map((c) => `${c.name} sameSite=${c.sameSite} secure=${c.secure} path=${c.path}`);
console.log(JSON.stringify({ url: app.url().split("?")[0], context: context_, error, organisms, findings, unavailable, failures, cookies, granted }));
await browser.close();
const expected = EXPECT_FINDINGS.split(";").filter(Boolean).sort();
const ok = context_?.includes(EXPECT_NAME) && (!EXPECT_ORGANISM || organisms.some((o) => o.includes(EXPECT_ORGANISM))) &&
  JSON.stringify(findings) === JSON.stringify(expected);
process.exit(ok ? 0 : 1);
