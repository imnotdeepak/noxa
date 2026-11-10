import { createClient } from "npm:@supabase/supabase-js@2";
import { requestPostHogDeletion } from "./posthog.mjs";
import { deleteRevenueCatCustomer, revenueCatConfig } from "./revenuecat.mjs";
import { deleteAccount } from "./workflow.mjs";
import { deletionJobs } from "./jobs.mjs";

const jsonHeaders = { "Content-Type": "application/json" };
const json = (status: number, body: object) =>
  new Response(JSON.stringify(body), { status, headers: jsonHeaders });

Deno.serve(async (request) => {
  if (request.method !== "POST") return json(405, { error: "method_not_allowed" });

  const authorization = request.headers.get("Authorization");
  const supabaseURL = Deno.env.get("SUPABASE_URL");
  const publishableKey = Deno.env.get("SUPABASE_ANON_KEY");
  const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");

  if (!authorization || !supabaseURL || !publishableKey || !serviceRoleKey) {
    return json(401, { error: "unauthorized" });
  }

  const userClient = createClient(supabaseURL, publishableKey, {
    global: { headers: { Authorization: authorization } },
    auth: { persistSession: false },
  });
  const { data, error: userError } = await userClient.auth.getUser();

  if (userError || !data.user) return json(401, { error: "invalid_session" });

  const adminClient = createClient(supabaseURL, serviceRoleKey, {
    auth: { persistSession: false },
  });
  const revenueCat = revenueCatConfig(Deno.env);

  const result = await deleteAccount(data.user.id, {
    revenueCat: revenueCat
      ? (userID: string) => deleteRevenueCatCustomer(revenueCat, userID)
      : null,
    deleteAuthUser: (userID: string) => adminClient.auth.admin.deleteUser(userID),
    requestAnalyticsDeletion: (userID: string) => requestPostHogDeletion(Deno.env, userID),
    jobs: deletionJobs(adminClient),
  });

  return json(result.status, result.body);
});
