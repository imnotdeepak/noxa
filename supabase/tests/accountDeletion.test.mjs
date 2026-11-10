import assert from "node:assert/strict";
import test from "node:test";
import {
  appUserIDFor,
  customerURL,
  deleteRevenueCatCustomer,
  RevenueCatError,
  revenueCatConfig,
} from "../functions/delete-account/revenuecat.mjs";
import { deleteAccount, JobStatus, sweepPendingDeletions } from "../functions/delete-account/workflow.mjs";

const userID = "8F14E45F-CEEA-467A-9575-1C4B2F2A1B10";
const appUserID = userID.toLowerCase();
const anonymous = "$RCAnonymousID:25609925c9244ef4b34202b3dae6483e";
const config = { secretKey: "sk_test", projectID: "proj1", host: "https://rc.test" };
const noSleep = async () => {};
const quietLog = { error() {} };

const response = (status, body = {}, headers = {}) => ({
  ok: status >= 200 && status < 300,
  status,
  headers: { get: (name) => headers[name] ?? null },
  json: async () => body,
});

/**
 * A fake RevenueCat project. Deleting any ID of a customer removes the whole
 * customer after `deleteLag` reads, to mimic RevenueCat's queued deletion.
 */
function fakeRevenueCat({ customers = {}, failures = [], deleteLag = 0, aliasDeleteRemovesAll = true } = {}) {
  const state = structuredClone(customers); // id -> { aliases: [], active: bool }
  const calls = [];
  const pendingDeletes = new Map(); // id -> reads left
  const owner = (id) => Object.keys(state).find((key) => key === id || state[key].aliases.includes(id));
  const fetchImpl = async (url, init) => {
    calls.push({ method: init.method, url, auth: init.headers.Authorization });
    const failure = failures.shift();
    if (failure) return typeof failure === "function" ? failure() : failure;
    const path = decodeURIComponent(new URL(url).pathname);
    const match = path.match(/^\/v2\/projects\/proj1\/customers\/([^/]+)(\/aliases)?$/);
    if (!match) return response(400);
    const [, id, aliases] = match;
    for (const [key, left] of pendingDeletes) {
      if (left <= 0) {
        const root = owner(key);
        if (root && (aliasDeleteRemovesAll || root === key)) delete state[root];
        else if (root) state[root].aliases = state[root].aliases.filter((a) => a !== key);
        pendingDeletes.delete(key);
      } else pendingDeletes.set(key, left - 1);
    }
    const root = owner(id);
    if (init.method === "DELETE") {
      if (!root) return response(404);
      pendingDeletes.set(id, deleteLag);
      if (deleteLag === 0) {
        if (aliasDeleteRemovesAll || root === id) delete state[root];
        else state[root].aliases = state[root].aliases.filter((a) => a !== id);
        pendingDeletes.delete(id);
      }
      return response(200, { object: "customer", id, deleted_at: 1 });
    }
    if (!root) return response(404, { type: "resource_missing" });
    if (aliases) {
      return response(200, { object: "list", items: [root, ...state[root].aliases].map((a) => ({ object: "customer.alias", id: a })), next_page: null });
    }
    return response(200, { id: root, active_entitlements: { items: state[root].active ? [{ entitlement_id: "pro" }] : [] } });
  };
  return { fetchImpl, calls, state };
}

function fakeJobs() {
  const rows = new Map();
  return {
    rows,
    async save(id, fields) { rows.set(id, { user_id: id, attempts: 0, ...rows.get(id), ...fields }); },
    async remove(id) { rows.delete(id); },
    async listVerifying() { return [...rows.values()].filter((row) => row.status === JobStatus.verifying); },
  };
}

function workflowDeps({ revenueCat, authError = null, analytics = "requested" } = {}) {
  const jobs = fakeJobs();
  const deletedUsers = [];
  return {
    jobs,
    deletedUsers,
    deps: {
      revenueCat,
      jobs,
      deleteAuthUser: async (id) => { if (!authError) deletedUsers.push(id); return { error: authError }; },
      requestAnalyticsDeletion: async () => analytics,
      log: quietLog,
    },
  };
}

// --- RevenueCat client ---

test("config needs a secret key and project, and keeps them server-side", () => {
  const env = (values) => ({ get: (key) => values[key] });
  assert.equal(revenueCatConfig(env({})), null);
  assert.equal(revenueCatConfig(env({ REVENUECAT_SECRET_KEY: "sk" })), null);
  assert.deepEqual(revenueCatConfig(env({ REVENUECAT_SECRET_KEY: "sk", REVENUECAT_PROJECT_ID: "p" })), {
    secretKey: "sk", projectID: "p", host: "https://api.revenuecat.com",
  });
});

test("the App User ID is the lowercased account ID and anonymous aliases are URL-encoded", () => {
  assert.equal(appUserIDFor(userID), appUserID);
  assert.equal(
    customerURL(config, anonymous),
    "https://rc.test/v2/projects/proj1/customers/%24RCAnonymousID%3A25609925c9244ef4b34202b3dae6483e",
  );
});

test("deletes the customer with its anonymous alias and confirms both are gone", async () => {
  const rc = fakeRevenueCat({ customers: { [appUserID]: { aliases: [anonymous], active: true } } });
  const result = await deleteRevenueCatCustomer(config, userID, { fetchImpl: rc.fetchImpl, sleep: noSleep });
  assert.deepEqual(result, { status: "deleted", customerIDs: [appUserID, anonymous], hadActiveSubscription: true });
  assert.deepEqual(rc.state, {});
  assert.ok(rc.calls.every((call) => call.auth === "Bearer sk_test"));
});

test("an alias that survives the main deletion is deleted on its own", async () => {
  const rc = fakeRevenueCat({
    customers: { [appUserID]: { aliases: [anonymous] } },
    aliasDeleteRemovesAll: false,
  });
  // Deleting the root removes the whole record in this fake; make the alias a
  // separate customer instead to model a non-merged anonymous record.
  rc.state[anonymous] = { aliases: [] };
  const result = await deleteRevenueCatCustomer(config, userID, { fetchImpl: rc.fetchImpl, sleep: noSleep });
  assert.equal(result.status, "deleted");
  assert.deepEqual(rc.state, {});
  assert.ok(rc.calls.some((call) => call.method === "DELETE" && call.url.includes("%24RCAnonymousID")));
});

test("no customer in RevenueCat is reported as absent without deleting anything", async () => {
  const rc = fakeRevenueCat();
  const result = await deleteRevenueCatCustomer(config, userID, { fetchImpl: rc.fetchImpl, sleep: noSleep });
  assert.equal(result.status, "absent");
  assert.equal(rc.calls.filter((call) => call.method === "DELETE").length, 0);
});

test("a queued deletion that is still readable is reported as queued, not deleted", async () => {
  const rc = fakeRevenueCat({ customers: { [appUserID]: { aliases: [] } }, deleteLag: 100 });
  const result = await deleteRevenueCatCustomer(config, userID, { fetchImpl: rc.fetchImpl, sleep: noSleep });
  assert.equal(result.status, "queued");
});

test("rate limits and server errors are retried, honouring Retry-After", async () => {
  const waits = [];
  const rc = fakeRevenueCat({
    customers: { [appUserID]: { aliases: [] } },
    failures: [response(429, { retryable: true }, { "Retry-After": "2" }), response(503)],
  });
  const result = await deleteRevenueCatCustomer(config, userID, {
    fetchImpl: rc.fetchImpl,
    sleep: async (ms) => { waits.push(ms); },
  });
  assert.equal(result.status, "deleted");
  assert.equal(waits[0], 2000);
  assert.equal(waits.length, 2);
});

test("an unreachable RevenueCat throws a retryable error after three attempts", async () => {
  let calls = 0;
  const fetchImpl = async () => { calls += 1; throw new Error("offline"); };
  await assert.rejects(
    deleteRevenueCatCustomer(config, userID, { fetchImpl, sleep: noSleep }),
    (error) => error instanceof RevenueCatError && error.retryable,
  );
  assert.equal(calls, 3);
});

test("a rejected secret key fails at once and is not retryable", async () => {
  let calls = 0;
  const fetchImpl = async () => { calls += 1; return response(403, { type: "authorization_error" }); };
  await assert.rejects(
    deleteRevenueCatCustomer(config, userID, { fetchImpl, sleep: noSleep }),
    (error) => error instanceof RevenueCatError && !error.retryable && error.status === 403,
  );
  assert.equal(calls, 1);
});

// --- Deletion order ---

test("successful deletion removes RevenueCat, then the account, then requests analytics deletion", async () => {
  const order = [];
  const { deps, jobs } = workflowDeps({
    revenueCat: async () => { order.push("revenuecat"); return { status: "deleted", customerIDs: [appUserID], hadActiveSubscription: false }; },
  });
  deps.deleteAuthUser = async () => { order.push("auth"); return { error: null }; };
  deps.requestAnalyticsDeletion = async () => { order.push("posthog"); return "requested"; };
  const result = await deleteAccount(userID, deps);
  assert.equal(result.status, 200);
  assert.deepEqual(result.body, { deleted: true, analytics: "requested", subscriptionRecord: "deleted", hadActiveSubscription: false });
  assert.deepEqual(order, ["revenuecat", "auth", "revenuecat", "posthog"]);
  assert.equal(jobs.rows.size, 0);
});

test("deletion with an active Apple subscription still deletes immediately and reports it", async () => {
  const rc = fakeRevenueCat({ customers: { [appUserID]: { aliases: [anonymous], active: true } } });
  const { deps, deletedUsers } = workflowDeps({
    revenueCat: (id) => deleteRevenueCatCustomer(config, id, { fetchImpl: rc.fetchImpl, sleep: noSleep }),
  });
  const result = await deleteAccount(userID, deps);
  assert.equal(result.status, 200);
  assert.equal(result.body.deleted, true);
  assert.equal(result.body.hadActiveSubscription, true);
  assert.equal(result.body.subscriptionRecord, "deleted");
  assert.deepEqual(deletedUsers, [userID]);
  assert.deepEqual(rc.state, {});
  // Nothing in the response claims Apple billing was cancelled.
  assert.ok(!JSON.stringify(result.body).toLowerCase().includes("cancel"));
});

test("a RevenueCat failure deletes nothing and leaves a job; a retry then succeeds", async () => {
  let rcUp = false;
  const rc = fakeRevenueCat({ customers: { [appUserID]: { aliases: [] , active: true } } });
  const { deps, jobs, deletedUsers } = workflowDeps({
    revenueCat: (id) => rcUp
      ? deleteRevenueCatCustomer(config, id, { fetchImpl: rc.fetchImpl, sleep: noSleep })
      : Promise.reject(new RevenueCatError("503", { status: 503, retryable: true })),
  });
  let analyticsCalls = 0;
  deps.requestAnalyticsDeletion = async () => { analyticsCalls += 1; return "requested"; };

  const failed = await deleteAccount(userID, deps);
  assert.equal(failed.status, 502);
  assert.deepEqual(failed.body, { error: "subscription_cleanup_failed", retryable: true });
  assert.deepEqual(deletedUsers, []);
  assert.equal(analyticsCalls, 0);
  assert.equal(jobs.rows.get(userID).status, JobStatus.pending);
  assert.ok(rc.state[appUserID]);

  rcUp = true;
  const retried = await deleteAccount(userID, deps);
  assert.equal(retried.status, 200);
  assert.deepEqual(deletedUsers, [userID]);
  assert.deepEqual(rc.state, {});
  assert.equal(jobs.rows.size, 0);
});

test("if the account deletion fails after RevenueCat, a retry finishes without error", async () => {
  const rc = fakeRevenueCat({ customers: { [appUserID]: { aliases: [] } } });
  const { deps, jobs } = workflowDeps({
    revenueCat: (id) => deleteRevenueCatCustomer(config, id, { fetchImpl: rc.fetchImpl, sleep: noSleep }),
    authError: { message: "db down" },
  });
  const failed = await deleteAccount(userID, deps);
  assert.equal(failed.status, 500);
  assert.equal(jobs.rows.get(userID).status, JobStatus.pending);

  deps.deleteAuthUser = async () => ({ error: null });
  const retried = await deleteAccount(userID, deps);
  assert.equal(retried.status, 200);
  assert.equal(retried.body.subscriptionRecord, "deleted");
});

test("a customer recreated by the app between steps is caught by the second pass", async () => {
  const rc = fakeRevenueCat({ customers: { [appUserID]: { aliases: [] } } });
  const { deps } = workflowDeps({
    revenueCat: (id) => deleteRevenueCatCustomer(config, id, { fetchImpl: rc.fetchImpl, sleep: noSleep }),
  });
  deps.deleteAuthUser = async () => {
    rc.state[appUserID] = { aliases: [], active: true }; // SDK posted the receipt again
    return { error: null };
  };
  const result = await deleteAccount(userID, deps);
  assert.equal(result.body.subscriptionRecord, "deleted");
  assert.deepEqual(rc.state, {});
});

test("an unconfirmed RevenueCat deletion is reported and kept for the sweeper", async () => {
  let pass = 0;
  const { deps, jobs } = workflowDeps({
    revenueCat: async () => {
      pass += 1;
      if (pass === 1) return { status: "deleted", customerIDs: [appUserID], hadActiveSubscription: true };
      throw new RevenueCatError("503", { retryable: true });
    },
  });
  const result = await deleteAccount(userID, deps);
  assert.equal(result.status, 200);
  assert.equal(result.body.subscriptionRecord, "pending_verification");
  assert.equal(jobs.rows.get(userID).status, JobStatus.verifying);

  const swept = await sweepPendingDeletions({
    jobs,
    revenueCat: async () => ({ status: "absent", customerIDs: [], hadActiveSubscription: false }),
    log: quietLog,
  });
  assert.deepEqual(swept, { confirmed: 1, remaining: 0 });
  assert.equal(jobs.rows.size, 0);
});

test("a failed sweep keeps the job and counts the attempt", async () => {
  const jobs = fakeJobs();
  await jobs.save(userID, { status: JobStatus.verifying });
  const swept = await sweepPendingDeletions({
    jobs,
    revenueCat: async () => { throw new RevenueCatError("429", { retryable: true }); },
    log: quietLog,
  });
  assert.deepEqual(swept, { confirmed: 0, remaining: 1 });
  assert.equal(jobs.rows.get(userID).attempts, 1);
});

test("without RevenueCat configured, deletion is refused rather than leaving the customer", async () => {
  const { deps, deletedUsers, jobs } = workflowDeps({ revenueCat: null });
  const result = await deleteAccount(userID, deps);
  assert.equal(result.status, 503);
  assert.equal(result.body.error, "subscription_cleanup_unavailable");
  assert.deepEqual(deletedUsers, []);
  assert.equal(jobs.rows.size, 0);
});

test("analytics failures never undo a completed deletion", async () => {
  const { deps } = workflowDeps({
    revenueCat: async () => ({ status: "absent", customerIDs: [], hadActiveSubscription: false }),
    analytics: "failed",
  });
  const result = await deleteAccount(userID, deps);
  assert.equal(result.status, 200);
  assert.equal(result.body.analytics, "failed");
});
