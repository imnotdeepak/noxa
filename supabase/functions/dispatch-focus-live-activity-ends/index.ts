import { createClient } from "npm:@supabase/supabase-js@2";
import { importPKCS8, SignJWT } from "npm:jose@5";
import { deliveryStatus, endPayload } from "./liveActivity.mjs";

const json = (status: number, body: object) =>
  new Response(JSON.stringify(body), { status, headers: { "Content-Type": "application/json" } });

async function sendEndPush(
  environment: "sandbox" | "production", token: string, bearer: string,
  bundleID: string, payload: object,
): Promise<{ status: number; reason: string }> {
  const host = environment === "sandbox"
    ? "https://api.sandbox.push.apple.com" : "https://api.push.apple.com";
  try {
    const response = await fetch(`${host}/3/device/${token}`, {
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
    if (response.ok) return { status: response.status, reason: "" };
    const errorBody = await response.json().catch(() => ({}));
    return {
      status: response.status,
      reason: String(errorBody.reason ?? `http_${response.status}`).slice(0, 100),
    };
  } catch {
    return { status: 503, reason: "network_error" };
  }
}

Deno.serve(async (request) => {
  if (request.method !== "POST") return json(405, { error: "method_not_allowed" });
  const secret = Deno.env.get("NOXA_LIVE_ACTIVITY_CRON_SECRET");
  if (!secret || request.headers.get("x-noxa-cron-secret") !== secret) {
    return json(401, { error: "unauthorized" });
  }
  const url = Deno.env.get("SUPABASE_URL");
  const service = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  const team = Deno.env.get("APNS_TEAM_ID");
  const bundleID = Deno.env.get("APNS_BUNDLE_ID");
  const sharedKeyID = Deno.env.get("APNS_KEY_ID");
  const sharedPrivateKey = Deno.env.get("APNS_PRIVATE_KEY");
  const credentials = {
    sandbox: {
      keyID: Deno.env.get("APNS_SANDBOX_KEY_ID") ?? sharedKeyID,
      privateKey: Deno.env.get("APNS_SANDBOX_PRIVATE_KEY") ?? sharedPrivateKey,
    },
    production: {
      keyID: Deno.env.get("APNS_PRODUCTION_KEY_ID") ?? sharedKeyID,
      privateKey: Deno.env.get("APNS_PRODUCTION_PRIVATE_KEY") ?? sharedPrivateKey,
    },
  };
  if (!url || !service || !team || !bundleID ||
      !credentials.sandbox.keyID || !credentials.sandbox.privateKey ||
      !credentials.production.keyID || !credentials.production.privateKey) {
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
  const bearers = {} as Record<"sandbox" | "production", string>;
  for (const environment of ["sandbox", "production"] as const) {
    const credential = credentials[environment];
    const key = await importPKCS8(credential.privateKey!.replace(/\\n/g, "\n"), "ES256");
    bearers[environment] = await new SignJWT({})
      .setProtectedHeader({ alg: "ES256", kid: credential.keyID! })
      .setIssuer(team).setIssuedAt().sign(key);
  }
  let sent = 0;
  let failed = 0;

  for (const row of due ?? []) {
    const { data: claimed, error: claimError } = await admin.from("focus_live_activity_ends")
      .update({ status: "sending", updated_at: now.toISOString() })
      .eq("user_id", row.user_id).eq("session_id", row.session_id)
      .eq("status", "pending").select("session_id");
    if (claimError || !claimed?.length) continue;

    const payload = endPayload(row.started_at, row.planned_end_at);
    let environment: "sandbox" | "production" = row.apns_environment === "sandbox"
      ? "sandbox" : "production";
    let result = await sendEndPush(
      environment, row.push_token, bearers[environment], bundleID, payload,
    );
    // A development-signed Release build can carry a sandbox token. APNs is
    // authoritative about the token's environment, so retry only this error.
    if (result.status === 400 && result.reason === "BadDeviceToken") {
      environment = environment === "sandbox" ? "production" : "sandbox";
      result = await sendEndPush(
        environment, row.push_token, bearers[environment], bundleID, payload,
      );
    }

    const attempts = row.attempts + 1;
    const nextStatus = deliveryStatus(result.status, attempts);
    await admin.from("focus_live_activity_ends").update({
      status: nextStatus,
      attempts,
      apns_environment: environment,
      last_error: result.status === 200 ? null : result.reason,
      updated_at: new Date().toISOString(),
    }).eq("user_id", row.user_id).eq("session_id", row.session_id).eq("status", "sending");
    if (result.status === 200) sent++; else failed++;
  }

  await admin.from("focus_live_activity_ends").delete()
    .lt("planned_end_at", new Date(Date.now() - 24 * 60 * 60_000).toISOString());
  return json(200, { sent, failed });
});
