/**
 * E2E test for the Agent Conversation feature.
 *
 * Runs **live** against the local stack:
 *   - Vite dev server (http://localhost:5173)
 *   - Local FastAPI backend (http://localhost:8000) calling real Foundry
 *     project `zava-project` on `foundry-zava-demo`, which in turn calls
 *     the deployed LangGraph ops-agent on AKS via A2A.
 *
 * Validates the 10-step test plan:
 *   1. Initial state — tab switcher renders, conversation default, empty state
 *   2. Tab switching works in both directions
 *   3. Submit form
 *   4. Wait for A2A bubbles (outbound + inbound)
 *   5. Outbound bubble references the order
 *   6. Inbound bubble renders the worker reply
 *   7. Raw JSON toggle works
 *   8. Security check — no leaked auth tokens in rendered DOM
 *   9. Tab badges update with counts
 *  10. Resubmit once if the orchestrator transient-bypassed A2A on first try
 *
 * Screenshots are saved under
 *   ../../agent-reports/agent-conversation-screenshots/
 */
import { test, expect, Page } from "@playwright/test";
import * as path from "path";
import { fileURLToPath } from "url";

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

const SCREENSHOT_DIR = path.resolve(
  __dirname,
  "..",
  "..",
  "..",
  "agent-reports",
  "agent-conversation-screenshots",
);

function snap(page: Page, name: string) {
  return page.screenshot({
    path: path.join(SCREENSHOT_DIR, name),
    fullPage: false,
  });
}

async function submitOrder(page: Page) {
  // SKU is a <select> — pick the ZP-7000 option.
  const sku = page.getByLabel(/^SKU$/i);
  if (await sku.count()) await sku.selectOption({ label: /^ZP-7000/ });
  const qty = page.getByLabel(/^Quantity$/i);
  if (await qty.count()) await qty.fill("150");
  const date = page.getByLabel(/^Target date$/i);
  if (await date.count()) await date.fill("2026-07-15");
  const customer = page.getByLabel(/^Customer$/i);
  if (await customer.count()) await customer.selectOption({ label: /^CUST-001/ });
  const submit = page.getByRole("button", { name: /check feasibility/i }).first();
  await submit.click();
}

test("agent conversation panel works end-to-end against live backend", async ({
  page,
}) => {
  test.setTimeout(240_000);

  // --- Step 1: initial state ---------------------------------------------
  await page.goto("/");
  await expect(page.locator("text=Foundry CS Agent").first()).toBeVisible();
  await expect(page.locator("text=LangGraph Ops Agent").first()).toBeVisible();

  const tabConv = page.getByTestId("tab-conversation");
  const tabTimeline = page.getByTestId("tab-timeline");
  await expect(tabConv).toBeVisible();
  await expect(tabTimeline).toBeVisible();
  await expect(tabConv).toHaveAttribute("aria-selected", "true");
  await expect(page.getByTestId("conversation-empty")).toBeVisible();
  await snap(page, "01-initial-state.png");

  // --- Step 2: tab switching ---------------------------------------------
  await tabTimeline.click();
  await expect(tabTimeline).toHaveAttribute("aria-selected", "true");
  await expect(page.locator(".timeline, .timeline__empty").first()).toBeVisible();
  await snap(page, "02-timeline-tab.png");
  await tabConv.click();
  await expect(tabConv).toHaveAttribute("aria-selected", "true");

  // --- Step 3 & 4: submit + wait for bubbles -----------------------------
  await submitOrder(page);
  const outbound = page.getByTestId("agent-bubble-outbound").first();
  const inbound = page.getByTestId("agent-bubble-inbound").first();

  let bypassedOnce = false;
  try {
    await Promise.all([
      outbound.waitFor({ state: "visible", timeout: 110_000 }),
      inbound.waitFor({ state: "visible", timeout: 110_000 }),
    ]);
  } catch {
    bypassedOnce = true;
    console.log("First attempt produced no A2A bubbles — resubmitting once.");
    await snap(page, "03a-bypass-first-attempt.png");
    await submitOrder(page);
    await Promise.all([
      outbound.waitFor({ state: "visible", timeout: 120_000 }),
      inbound.waitFor({ state: "visible", timeout: 120_000 }),
    ]);
  }
  await snap(page, "03-conversation-populated.png");

  // --- Step 5: outbound bubble references the order ----------------------
  const outboundText = (await outbound.innerText()).toLowerCase();
  expect(
    outboundText.includes("zp-7000") ||
      outboundText.includes("feasibility") ||
      outboundText.includes("sku"),
    `outbound bubble text was: ${outboundText.slice(0, 400)}`,
  ).toBeTruthy();
  await expect(outbound.locator(".bubble__sender")).toContainText(
    /Foundry CS Agent/,
  );

  // --- Step 6: inbound bubble renders worker reply -----------------------
  const inboundText = (await inbound.innerText()).trim();
  expect(
    inboundText.length,
    "inbound bubble should have non-trivial worker reply text",
  ).toBeGreaterThan(20);
  await expect(inbound.locator(".bubble__sender")).toContainText(
    /LangGraph Ops Agent/,
  );
  // If the worker emitted a DataPart we should see at least one structured row,
  // but the GA worker currently replies with prose only — don't hard-fail.
  const inboundDtCount = await inbound.locator("dl.bubble__data dt").count();
  console.log(`inbound bubble structured rows: ${inboundDtCount}`);

  // --- Step 7: raw JSON toggle works -------------------------------------
  const rawDetails = inbound.locator("details.bubble__raw");
  await rawDetails.locator("summary").click();
  await expect(inbound.locator("pre.bubble__raw-pre")).toBeVisible();
  await snap(page, "04-raw-json-expanded.png");

  // --- Step 8: redaction sanity check ------------------------------------
  const html = (await page.content()).toLowerCase();
  const bearerMatches = html.match(/"?bearer\s+[a-z0-9._\-]{20,}/g) || [];
  expect(
    bearerMatches.length,
    `unexpected bearer-looking tokens in DOM: ${bearerMatches.slice(0, 3).join(", ")}`,
  ).toBe(0);
  const authHeader = html.match(/"authorization"\s*:\s*"(?!\*{3,}redacted)/g) || [];
  expect(
    authHeader.length,
    `unredacted "authorization" header values present: ${authHeader.slice(0, 3).join(", ")}`,
  ).toBe(0);

  // --- Step 9: tab badges update -----------------------------------------
  const convBadge = await tabConv.locator(".tab__badge").innerText();
  expect(parseInt(convBadge, 10)).toBeGreaterThanOrEqual(2);
  const timelineBadge = await tabTimeline.locator(".tab__badge").innerText();
  expect(parseInt(timelineBadge, 10)).toBeGreaterThanOrEqual(1);

  await snap(page, "05-final-state.png");

  if (bypassedOnce) {
    console.log(
      "NOTE: first submit triggered the known Foundry GA bypass; second submit succeeded.",
    );
  }
});
