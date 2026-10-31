# Noxa Supabase setup

1. Open the Supabase dashboard for the Noxa project.
2. Open **SQL Editor**, create a new query, paste [`schema.sql`](./schema.sql), and run it.
3. Confirm the tables and RLS policies appear under **Database → Tables**.
4. Test with a normal authenticated account. Never put a service-role key in the iOS app.

If you ran an earlier stage-three draft, run the complete SQL file again. It
migrates existing focus-session rows to the new explicit `outcome` field before
the updated iOS client attempts synchronization.

The app writes profile metadata, website domains, and focus-session history after a
user signs in. Writes are local-first and retry after a network failure. Family
Activity selections, Apple Screen Time tokens, active shields, schedules, and raw
Screen Time usage remain device-local by design.

The iOS app does not apply this SQL automatically and does not need a database
password. `replace_website_blocklist` is a user-scoped function: it uses the
caller’s `auth.uid()` and accepts no user ID from the client.

## Account deletion function

Deploy the authenticated Edge Function before testing the in-app **Delete
Account** button:

```sh
supabase functions deploy delete-account
```

The function validates the caller's access token before using Supabase's
server-only service-role environment variable to delete that exact Auth user.
Foreign-key cascades remove the user's product rows. The iOS app clears local
Screen Time configuration only after the server confirms deletion.

It also asks PostHog to delete the analytics person the app identified by that
user ID, along with their events. Set these secrets to enable it:

- `POSTHOG_PERSONAL_API_KEY`: a PostHog personal API key with the
  `person:write` scope. Server-only; never put it in the app.
- `POSTHOG_PROJECT_ID`: the numeric project ID from PostHog's project settings.
- `POSTHOG_API_HOST` (optional): defaults to `https://us.posthog.com`; use
  `https://eu.posthog.com` for an EU project.

Without them the function still deletes the account and reports
`"analytics": "skipped"`. A PostHog error is logged and reported as
`"failed"`, but never blocks the account deletion. PostHog processes person
deletions in the background, so the record can take a while to disappear.

## Minimum supported iPhone build

The public `release-policy` function returns `minimumIOSBuild`. It defaults to
`0`, so deploying it does not require anyone to update. Noxa caches the last
successful value and checks again when opened or returned to the foreground.
Set the `MINIMUM_IOS_BUILD` Supabase secret to a build number **only after that
build is available on the App Store**, and only when an older build cannot
safely continue. Lower the value to undo a mistaken requirement. Active Focus
and Pomodoro sessions stay on their existing screen until they end; their
Screen Time callbacks, schedules, and daily limits continue independently of
this check. Versions released before this check was added cannot be gated
remotely, so data migration is still required.

## Live Activity removal while Noxa is closed

The optional Lock Screen Live Activity uses a per-activity Apple push token so
the server can dismiss it after the planned focus end. The app still dismisses
it locally when running. This record contains the session UUID, start/end
timestamps, APNs environment, and push token. It contains no selected apps,
websites, usage, or intention. The dispatch function deletes records 24 hours
after the planned end; account deletion removes them immediately.

For an existing project, first run
`migrations/20261022_focus_live_activity_ends.sql` in the SQL Editor. Fresh
projects receive the same table from `schema.sql`.

Before deploying, enable **Push Notifications** for the `LycheeCorp.Noxa` App ID
in Apple Developer and refresh the development/distribution provisioning
profiles. Create an APNs Auth Key with push access. Configure these Supabase
Edge Function secrets (keep the private key and cron secret out of Git):

- `APNS_TEAM_ID`: Apple Developer team ID.
- `APNS_SANDBOX_KEY_ID` and `APNS_SANDBOX_PRIVATE_KEY`: development APNs key ID and full `.p8` contents.
- `APNS_PRODUCTION_KEY_ID` and `APNS_PRODUCTION_PRIVATE_KEY`: production APNs key ID and full `.p8` contents.
- `APNS_BUNDLE_ID`: `LycheeCorp.Noxa`.
- `NOXA_LIVE_ACTIVITY_CRON_SECRET`: a random server-only value.

Separate topic-specific keys for `LycheeCorp.Noxa` keep sandbox and production
access limited to this app. If your Apple team already has one APNs key valid
for both environments, the dispatcher also accepts the older shared
`APNS_KEY_ID` and `APNS_PRIVATE_KEY` secrets as a fallback.

Deploy both functions:

```sh
supabase functions deploy focus-live-activity
supabase functions deploy dispatch-focus-live-activity-ends --no-verify-jwt
```

In Supabase Cron, schedule an HTTP POST to
`https://ckwikbybjgydfcqpnfyo.supabase.co/functions/v1/dispatch-focus-live-activity-ends`
every 30 seconds. Set header `x-noxa-cron-secret` to the same secret, and store
that value in Supabase Vault rather than the SQL/job definition. The dispatch
endpoint rejects requests without the secret. Monitor function logs and APNs
errors. A missed network delivery is retried up to five times for transient
errors. If APNs reports `BadDeviceToken`, the dispatcher tries the other APNs
environment once; this covers development-signed Release builds. The app also
reconciles on foreground. This path gives prompt
cleanup in normal connectivity; APNs cannot guarantee exact-second delivery.

With Supabase `pg_cron`, `pg_net`, and Vault enabled, one way to create the job
is to save the same cron secret in Vault under
`noxa_live_activity_cron_secret`, then run:

```sql
select cron.schedule(
  'noxa-live-activity-ends',
  '30 seconds',
  $$
    select net.http_post(
      url := 'https://ckwikbybjgydfcqpnfyo.supabase.co/functions/v1/dispatch-focus-live-activity-ends',
      headers := jsonb_build_object(
        'Content-Type', 'application/json',
        'x-noxa-cron-secret',
        (select decrypted_secret from vault.decrypted_secrets
         where name = 'noxa_live_activity_cron_secret')
      ),
      body := '{}'::jsonb
    );
  $$
);
```
