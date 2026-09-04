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
