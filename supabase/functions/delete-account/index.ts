import { createClient } from "npm:@supabase/supabase-js@2";

const jsonHeaders = { "Content-Type": "application/json" };

Deno.serve(async (request) => {
  if (request.method !== "POST") {
    return new Response(JSON.stringify({ error: "method_not_allowed" }), {
      status: 405,
      headers: jsonHeaders,
    });
  }

  const authorization = request.headers.get("Authorization");
  const supabaseURL = Deno.env.get("SUPABASE_URL");
  const publishableKey = Deno.env.get("SUPABASE_ANON_KEY");
  const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");

  if (!authorization || !supabaseURL || !publishableKey || !serviceRoleKey) {
    return new Response(JSON.stringify({ error: "unauthorized" }), {
      status: 401,
      headers: jsonHeaders,
    });
  }

  const userClient = createClient(supabaseURL, publishableKey, {
    global: { headers: { Authorization: authorization } },
    auth: { persistSession: false },
  });
  const { data, error: userError } = await userClient.auth.getUser();

  if (userError || !data.user) {
    return new Response(JSON.stringify({ error: "invalid_session" }), {
      status: 401,
      headers: jsonHeaders,
    });
  }

  const adminClient = createClient(supabaseURL, serviceRoleKey, {
    auth: { persistSession: false },
  });
  const { error: deletionError } = await adminClient.auth.admin.deleteUser(
    data.user.id,
  );

  if (deletionError) {
    console.error("Account deletion failed", deletionError.message);
    return new Response(JSON.stringify({ error: "deletion_failed" }), {
      status: 500,
      headers: jsonHeaders,
    });
  }

  return new Response(JSON.stringify({ deleted: true }), {
    status: 200,
    headers: jsonHeaders,
  });
});
