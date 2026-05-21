/**
 * Playwright config for the Zava Agent Conversation feature test.
 *
 * Runs against the **already-running** local dev stack:
 *   - Frontend (Vite):  http://localhost:5173
 *   - Backend  (FastAPI): http://localhost:8000 (proxied via /api)
 *
 * We deliberately do NOT auto-start the dev servers from this config so
 * we test the exact running build the user has been validating against.
 */
import { defineConfig, devices } from "@playwright/test";

export default defineConfig({
  testDir: "./e2e",
  timeout: 180_000,
  expect: { timeout: 30_000 },
  retries: 0,
  workers: 1,
  reporter: [["list"]],
  use: {
    baseURL: "http://localhost:5173",
    viewport: { width: 1920, height: 1080 },
    actionTimeout: 15_000,
    navigationTimeout: 30_000,
    trace: "retain-on-failure",
    screenshot: "only-on-failure",
  },
  projects: [
    {
      name: "chromium",
      use: { ...devices["Desktop Chrome"] },
    },
  ],
});
