// Account deletion jobs in public.account_deletion_jobs, written with the
// service-role client. Rows have no foreign key to auth.users so they outlive
// the account; a row is removed once RevenueCat confirms the deletion.

const TABLE = "account_deletion_jobs";

export function deletionJobs(adminClient) {
  return {
    async save(userID, fields) {
      const { error } = await adminClient.from(TABLE).upsert({
        user_id: userID,
        ...fields,
        updated_at: new Date().toISOString(),
      });
      if (error) throw new Error(error.message);
    },
    async remove(userID) {
      const { error } = await adminClient.from(TABLE).delete().eq("user_id", userID);
      if (error) throw new Error(error.message);
    },
    async listVerifying(limit) {
      const { data, error } = await adminClient.from(TABLE)
        .select("user_id, attempts")
        .eq("status", "verifying")
        .order("updated_at", { ascending: true })
        .limit(limit);
      if (error) throw new Error(error.message);
      return data ?? [];
    },
  };
}
