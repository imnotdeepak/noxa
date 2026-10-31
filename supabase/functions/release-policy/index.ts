// Raise MINIMUM_IOS_BUILD only after that build is available on the App Store.
// A value of 0 leaves every build eligible. This endpoint is intentionally
// public so Noxa can check it before sign-in or while an account is expired.
Deno.serve((request) => {
  if (request.method !== "GET") {
    return new Response(JSON.stringify({ error: "method_not_allowed" }), {
      status: 405,
      headers: { "Content-Type": "application/json", "Cache-Control": "no-store" },
    });
  }

  const configured = Number(Deno.env.get("MINIMUM_IOS_BUILD") ?? "0");
  const minimumIOSBuild = Number.isSafeInteger(configured)
    && configured >= 0 && configured <= 1_000_000 ? configured : 0;

  return new Response(JSON.stringify({ minimumIOSBuild }), {
    headers: { "Content-Type": "application/json", "Cache-Control": "no-store" },
  });
});
