// Deletes the RevenueCat customer behind a Noxa account, with every alias.
//
// Noxa logs RevenueCat in with the lowercased Supabase user ID, so that is the
// App User ID. RevenueCat merges anonymous IDs ($RCAnonymousID:…) into that
// customer as aliases, and Noxa's "Keep with original App User ID" restore
// rule pins the Apple purchase to it. Leaving the customer behind keeps the
// purchase linked to an account that no longer exists.
//
// Uses the REST API v2 with a secret key that has the
// customer_information:customers:read_write permission. The key must stay on
// the server. Deletion is queued by RevenueCat, so success is confirmed by
// reading each ID back until RevenueCat answers 404.

export class RevenueCatError extends Error {
  constructor(message, { status = 0, retryable = false } = {}) {
    super(message);
    this.name = "RevenueCatError";
    this.status = status;
    this.retryable = retryable;
  }
}

export function revenueCatConfig(env) {
  const secretKey = env.get("REVENUECAT_SECRET_KEY");
  const projectID = env.get("REVENUECAT_PROJECT_ID");
  if (!secretKey || !projectID) return null;
  const host = (env.get("REVENUECAT_API_HOST") ?? "https://api.revenuecat.com").replace(/\/+$/, "");
  return { secretKey, projectID, host };
}

export function appUserIDFor(userID) {
  return userID.toLowerCase();
}

export function customerURL(config, customerID, suffix = "") {
  return `${config.host}/v2/projects/${encodeURIComponent(config.projectID)}` +
    `/customers/${encodeURIComponent(customerID)}${suffix}`;
}

const RETRYABLE = new Set([423, 429, 500, 502, 503, 504]);
const MAX_WAIT_MS = 5_000;

/** How long RevenueCat asked us to wait, capped so a request stays short. */
export function retryDelay(response, body, attempt) {
  const header = Number(response?.headers?.get?.("Retry-After"));
  if (Number.isFinite(header) && header > 0) return Math.min(header * 1000, MAX_WAIT_MS);
  if (Number.isFinite(body?.backoff_ms) && body.backoff_ms > 0) return Math.min(body.backoff_ms, MAX_WAIT_MS);
  return Math.min(250 * 2 ** attempt, MAX_WAIT_MS);
}

/**
 * Sends one request, retrying rate limits, locks and server errors.
 * Returns { status, body }; 404 is a normal answer, not an error.
 */
export async function send(config, url, method, { fetchImpl = fetch, sleep = defaultSleep, maxAttempts = 3 } = {}) {
  let lastError;
  for (let attempt = 0; attempt < maxAttempts; attempt += 1) {
    let response;
    try {
      response = await fetchImpl(url, {
        method,
        headers: {
          "Authorization": `Bearer ${config.secretKey}`,
          "Content-Type": "application/json",
        },
      });
    } catch (error) {
      lastError = new RevenueCatError(`network: ${error?.message ?? error}`, { retryable: true });
      if (attempt + 1 < maxAttempts) await sleep(retryDelay(null, null, attempt));
      continue;
    }
    const body = await response.json().catch(() => null);
    if (response.ok || response.status === 404) return { status: response.status, body };
    const retryable = RETRYABLE.has(response.status) || body?.retryable === true;
    lastError = new RevenueCatError(`${method} ${response.status} ${body?.type ?? ""}`.trim(), {
      status: response.status,
      retryable,
    });
    if (!retryable) throw lastError;
    if (attempt + 1 < maxAttempts) await sleep(retryDelay(response, body, attempt));
  }
  throw lastError;
}

async function listAliases(config, appUserID, options) {
  const ids = [];
  let url = customerURL(config, appUserID, "/aliases?limit=100");
  for (let page = 0; url && page < 20; page += 1) {
    const { status, body } = await send(config, url, "GET", options);
    if (status === 404) return null;
    for (const item of body?.items ?? []) {
      if (typeof item?.id === "string") ids.push(item.id);
    }
    url = body?.next_page ? new URL(body.next_page, config.host).toString() : null;
  }
  return ids;
}

async function hasActiveEntitlement(config, appUserID, options) {
  const { status, body } = await send(config, customerURL(config, appUserID), "GET", options);
  if (status === 404) return false;
  return (body?.active_entitlements?.items?.length ?? 0) > 0;
}

async function exists(config, customerID, options) {
  const { status } = await send(config, customerURL(config, customerID), "GET", options);
  return status !== 404;
}

/**
 * Deletes the customer and confirms that it and each alias are gone.
 *
 * Returns { status, customerIDs, hadActiveSubscription } where status is
 *  - "absent":  RevenueCat had no customer for this account;
 *  - "deleted": every ID now reads back as 404;
 *  - "queued":  RevenueCat accepted the deletion but some ID still reads back,
 *               so the caller must keep tracking it until it is confirmed.
 * Throws RevenueCatError when RevenueCat cannot be reached or refuses.
 */
export async function deleteRevenueCatCustomer(config, userID, options = {}) {
  const { sleep = defaultSleep, verifyAttempts = 4, verifyDelayMs = 750 } = options;
  const appUserID = appUserIDFor(userID);
  const aliases = await listAliases(config, appUserID, options);
  if (aliases === null) {
    return { status: "absent", customerIDs: [], hadActiveSubscription: false };
  }
  const customerIDs = [...new Set([appUserID, ...aliases])];
  const hadActiveSubscription = await hasActiveEntitlement(config, appUserID, options);

  await send(config, customerURL(config, appUserID), "DELETE", options);

  // RevenueCat queues deletions and does not document whether deleting one
  // alias removes the others, so read every ID back and delete any that stay.
  let remaining = customerIDs;
  for (let attempt = 0; attempt < verifyAttempts && remaining.length > 0; attempt += 1) {
    if (attempt > 0) await sleep(verifyDelayMs);
    const stillThere = [];
    for (const id of remaining) {
      if (await exists(config, id, options)) stillThere.push(id);
    }
    remaining = stillThere;
    if (attempt > 0) {
      for (const id of remaining) {
        await send(config, customerURL(config, id), "DELETE", options);
      }
    }
  }

  return {
    status: remaining.length === 0 ? "deleted" : "queued",
    customerIDs,
    hadActiveSubscription,
  };
}

function defaultSleep(ms) {
  return new Promise((resolve) => setTimeout(resolve, ms));
}
