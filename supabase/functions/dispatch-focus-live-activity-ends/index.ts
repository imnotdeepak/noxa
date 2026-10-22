import { createClient } from "npm:@supabase/supabase-js@2";
import { importPKCS8, SignJWT } from "npm:jose@5";
import { deliveryStatus, endPayload } from "../_shared/liveActivity.mjs";

const json = (status: number, body: object) =>
  new Response(JSON.stringify(body), { status, headers: { "Content-Type": "application/json" } });

Deno.serve(async (request) => {
  if (request.method !== "POST") return json(405, { error: "method_not_allowed" });
  const secret = Deno.env.get("NOXA_LIVE_ACTIVITY_CRON_SECRET");
  if (!secret || request.headers.get("x-noxa-cron-secret") !== secret) {
    return json(401, { error: "unauthorized" });
  }
  const url = Deno.env.get("SUPABASE_URL");
  const service = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  const team = Deno.env.get("APNS_TEAM_ID");
  const keyID = Deno.env.get("APNS_KEY_ID");
  const privateKey = Deno.env.get("APNS_PRIVATE_KEY")?.replace(/\\n/g, "\n");
  const bundleID = Deno.env.get("APNS_BUNDLE_ID");
  if (!url || !service || !team || !keyID || !privateKey || !bundleID) {
    return json(503, { error: "not_configured" });
  }

  const admin = createClient(url, service, { auth: { persistSession: false } });
  const now = new Date();
  await admin.from("focus_live_activity_ends").update({ status: "pending" })
    .eq("status", "sending")
    .lt("updated_at", new Date(Date.now() - 5 * 60_000).toISOString());
  const { data: due, error: loadError } = await admin.from("focus_live_activity_ends")
    .select("user_id,session_id,push_token,apns_environment,started_at,planned_end_at,attempts")
    .eq("status", "pending").lte("planned_end_at", now.toISOString())
    .order("planned_end_at", { ascending: true }).limit(25);
  if (loadError) return json(500, { error: "load_failed" });
  const key = await importPKCS8(privateKey, "ES256");
  const bearer = await new SignJWT({}).setProtectedHeader({ alg: "ES256", kid: keyID })
    .setIssuer(team).setIssuedAt().sign(key);
  let sent = 0;
  let failed = 0;

  for (const row of due ?? []) {
    const { data: claimed, error: claimError } = await admin.from("focus_live_activity_ends")
      .update({ status: "sending", updated_at: now.toISOString() })
      .eq("user_id", row.user_id).eq("session_id", row.session_id)
      .eq("status", "pending").select("session_id");
    if (claimError || !claimed?.length) continue;

    const payload = endPayload(row.started_at, row.planned_end_at);
    const host = row.apns_environment === "sandbox"
      ? "https://api.sandbox.push.apple.com"
      : "https://api.push.apple.com";
    let status = 503;
    let reason = "network_error";
    try {
      const response = await fetch(`${host}/3/device/${row.push_token}`, {
        method: "POST",
        headers: {
          authorization: `bearer ${bearer}`,
          "apns-topic": `${bundleID}.push-type.liveactivity`,
          "apns-push-type": "liveactivity",
          "apns-priority": "10",
          "content-type": "application/json",
        },
        body: JSON.stringify(payload),
      });
      status = response.status;
      if (!response.ok) {
        const errorBody = await response.json().catch(() => ({}));
        reason = String(errorBody.reason ?? `http_${status}`).slice(0, 100);
      }
    } catch { /* Retry a network failure on the next dispatch. */ }

    const attempts = row.attempts + 1;
    const nextStatus = deliveryStatus(status, attempts);
    await admin.from("focus_live_activity_ends").update({
      status: nextStatus,
      attempts,
      last_error: status === 200 ? null : reason,
      updated_at: new Date().toISOString(),
    }).eq("user_id", row.user_id).eq("session_id", row.session_id).eq("status", "sending");
    if (status === 200) sent++; else failed++;
  }

  await admin.from("focus_live_activity_ends").delete()
    .lt("planned_end_at", new Date(Date.now() - 24 * 60 * 60_000).toISOString());
  return json(200, { sent, failed });
});
