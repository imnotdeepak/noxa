import { createClient } from "npm:@supabase/supabase-js@2";

const headers = { "Content-Type": "application/json" };
const respond = (status: number, body: object) =>
  new Response(JSON.stringify(body), { status, headers });

Deno.serve(async (request) => {
  if (request.method !== "POST") return respond(405, { error: "method_not_allowed" });
  const url = Deno.env.get("SUPABASE_URL");
  const anon = Deno.env.get("SUPABASE_ANON_KEY");
  const service = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  const authorization = request.headers.get("Authorization");
  if (!url || !anon || !service || !authorization) return respond(401, { error: "unauthorized" });

  const userClient = createClient(url, anon, {
    global: { headers: { Authorization: authorization } },
    auth: { persistSession: false },
  });
  const { data: { user }, error } = await userClient.auth.getUser();
  if (error || !user) return respond(401, { error: "invalid_session" });

  let body: Record<string, unknown>;
  try { body = await request.json(); }
  catch { return respond(400, { error: "invalid_json" }); }
  if (!body || typeof body !== "object" || Array.isArray(body)) {
    return respond(400, { error: "invalid_json" });
  }
  const sessionID = body.sessionID;
  if (typeof sessionID !== "string" ||
      !/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(sessionID)) {
    return respond(400, { error: "invalid_session_id" });
  }

  const admin = createClient(url, service, { auth: { persistSession: false } });
  if (body.action === "remove") {
    const { error: removeError } = await admin.from("focus_live_activity_ends")
      .delete().eq("user_id", user.id).eq("session_id", sessionID);
    return removeError ? respond(500, { error: "remove_failed" }) : respond(200, { ok: true });
  }
  if (body.action !== "register") return respond(400, { error: "invalid_action" });

  const token = body.pushToken;
  const environment = body.environment;
  const start = typeof body.startedAt === "string" ? Date.parse(body.startedAt) : NaN;
  const end = typeof body.plannedEndAt === "string" ? Date.parse(body.plannedEndAt) : NaN;
  const now = Date.now();
  if (typeof token !== "string" || !/^[0-9a-f]{64,512}$/i.test(token) ||
      (environment !== "sandbox" && environment !== "production") ||
      !Number.isFinite(start) || !Number.isFinite(end) ||
      start > now + 60_000 || end <= now || end > start + 8 * 60 * 60_000 ||
      end > now + 8 * 60 * 60_000) {
    return respond(400, { error: "invalid_activity" });
  }

  const { error: saveError } = await admin.from("focus_live_activity_ends").upsert({
    session_id: sessionID,
    user_id: user.id,
    push_token: token,
    apns_environment: environment,
    started_at: new Date(start).toISOString(),
    planned_end_at: new Date(end).toISOString(),
    status: "pending",
    attempts: 0,
    last_error: null,
    updated_at: new Date().toISOString(),
  }, { onConflict: "user_id,session_id" });
  if (saveError) {
    console.error("Live Activity registration failed", saveError.message);
    return respond(500, { error: "registration_failed" });
  }
  return respond(200, { ok: true });
});
