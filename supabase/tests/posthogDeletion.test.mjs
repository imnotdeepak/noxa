import assert from "node:assert/strict";
import test from "node:test";
import { deletionRequest, postHogConfig, requestPostHogDeletion } from "../functions/delete-account/posthog.mjs";

const env = (values) => ({ get: (key) => values[key] });
const userID = "8F14E45F-CEEA-467A-9575-1C4B2F2A1B10";

test("without a key or project ID, deletion is skipped and nothing is sent", async () => {
  let calls = 0;
  const fetchImpl = async () => { calls += 1; return { ok: true }; };
  assert.equal(await requestPostHogDeletion(env({}), userID, fetchImpl), "skipped");
  assert.equal(await requestPostHogDeletion(env({ POSTHOG_PERSONAL_API_KEY: "k" }), userID, fetchImpl), "skipped");
  assert.equal(calls, 0);
});

test("deletes the person by the lowercased user ID, with their events", () => {
  const config = postHogConfig(env({ POSTHOG_PERSONAL_API_KEY: "phx_key", POSTHOG_PROJECT_ID: "123" }));
  const { url, init } = deletionRequest(config, userID);
  assert.equal(url, "https://us.posthog.com/api/projects/123/persons/bulk_delete/");
  assert.equal(init.method, "POST");
  assert.equal(init.headers.Authorization, "Bearer phx_key");
  assert.deepEqual(JSON.parse(init.body), {
    distinct_ids: [userID.toLowerCase()],
    delete_events: true,
  });
});

test("a custom host is used without a trailing slash", () => {
  const config = postHogConfig(env({
    POSTHOG_PERSONAL_API_KEY: "k",
    POSTHOG_PROJECT_ID: "1",
    POSTHOG_API_HOST: "https://eu.posthog.com/",
  }));
  assert.equal(deletionRequest(config, userID).url, "https://eu.posthog.com/api/projects/1/persons/bulk_delete/");
});

test("PostHog errors are reported, never thrown", async () => {
  const configured = env({ POSTHOG_PERSONAL_API_KEY: "k", POSTHOG_PROJECT_ID: "1" });
  assert.equal(await requestPostHogDeletion(configured, userID, async () => ({ ok: true })), "requested");
  assert.equal(await requestPostHogDeletion(configured, userID, async () => ({ ok: false, status: 403 })), "failed");
  assert.equal(await requestPostHogDeletion(configured, userID, async () => { throw new Error("offline"); }), "failed");
});
