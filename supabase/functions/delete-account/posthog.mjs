// Asks PostHog to delete the analytics person (and their events) for a
// deleted Noxa account. The app identifies people by the lowercased Supabase
// user ID, so that is the distinct ID to delete.
//
// Needs a PostHog personal API key with the person:write scope, which must
// stay on the server. Without the key or project ID this reports "skipped".

export function postHogConfig(env) {
  const apiKey = env.get("POSTHOG_PERSONAL_API_KEY");
  const projectID = env.get("POSTHOG_PROJECT_ID");
  if (!apiKey || !projectID) return null;
  // The private API lives on us.posthog.com, not the us.i.posthog.com
  // ingestion host the app sends events to.
  const host = (env.get("POSTHOG_API_HOST") ?? "https://us.posthog.com").replace(/\/+$/, "");
  return { apiKey, projectID, host };
}

export function deletionRequest(config, userID) {
  return {
    url: `${config.host}/api/projects/${encodeURIComponent(config.projectID)}/persons/bulk_delete/`,
    init: {
      method: "POST",
      headers: {
        "Authorization": `Bearer ${config.apiKey}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        distinct_ids: [userID.toLowerCase()],
        delete_events: true,
      }),
    },
  };
}

/** Returns "requested", "skipped" or "failed"; never throws. */
export async function requestPostHogDeletion(env, userID, fetchImpl = fetch) {
  const config = postHogConfig(env);
  if (!config) return "skipped";
  try {
    const { url, init } = deletionRequest(config, userID);
    const response = await fetchImpl(url, init);
    if (response.ok) return "requested";
    console.error("PostHog deletion failed", response.status);
    return "failed";
  } catch (error) {
    console.error("PostHog deletion failed", error?.message ?? String(error));
    return "failed";
  }
}
