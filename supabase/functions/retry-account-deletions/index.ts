// Scheduled retry for RevenueCat cleanup of accounts that are already deleted.
// Called by cron with the x-noxa-cron-secret header.
import { createClient } from "npm:@supabase/supabase-js@2";
import { deleteRevenueCatCustomer, revenueCatConfig } from "../delete-account/revenuecat.mjs";
import { deletionJobs } from "../delete-account/jobs.mjs";
import { sweepPendingDeletions } from "../delete-account/workflow.mjs";

const json = (status: number, body: object) =>
  new Response(JSON.stringify(body), { status, headers: { "Content-Type": "application/json" } });

Deno.serve(async (request) => {
  if (request.method !== "POST") return json(405, { error: "method_not_allowed" });
  const secret = Deno.env.get("NOXA_ACCOUNT_DELETION_CRON_SECRET");
  if (!secret || request.headers.get("x-noxa-cron-secret") !== secret) {
    return json(401, { error: "unauthorized" });
  }
  const url = Deno.env.get("SUPABASE_URL");
  const service = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  const revenueCat = revenueCatConfig(Deno.env);
  if (!url || !service || !revenueCat) return json(503, { error: "not_configured" });

  const admin = createClient(url, service, { auth: { persistSession: false } });
  const result = await sweepPendingDeletions({
    jobs: deletionJobs(admin),
    revenueCat: (userID: string) => deleteRevenueCatCustomer(revenueCat, userID),
  });
  return json(200, result);
});
