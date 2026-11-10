// The order of account deletion. Kept free of Deno and Supabase so it can be
// tested with fakes.
//
//  1. Record a deletion job. It has no foreign key to the user, so it outlives
//     them and a RevenueCat record can never be left behind untracked.
//  2. Delete the RevenueCat customer and its aliases. If that fails, stop:
//     nothing else has been deleted and the user can simply try again.
//  3. Delete the Supabase user (product rows cascade).
//  4. Check RevenueCat once more, because the app's SDK can recreate the
//     customer between steps 2 and 3. Anything unconfirmed stays as a job the
//     sweeper retries, and the response says so.
//  5. Request PostHog deletion; its failure never undoes the above.
//
// Apple billing is untouched: deleting a Noxa account cannot cancel an App
// Store subscription, and nothing here claims to.

export const JobStatus = Object.freeze({
  pending: "pending", // the account still exists
  verifying: "verifying", // the account is gone; RevenueCat is not yet confirmed
});

/**
 * deps:
 *  - revenueCat(userID) -> { status, customerIDs, hadActiveSubscription }, throws on failure
 *  - deleteAuthUser(userID) -> { error }
 *  - requestAnalyticsDeletion(userID) -> "requested" | "skipped" | "failed"
 *  - jobs: { save(userID, fields), remove(userID) }
 */
export async function deleteAccount(userID, deps) {
  const { revenueCat, deleteAuthUser, requestAnalyticsDeletion, jobs, log = console } = deps;

  if (!revenueCat) {
    log.error("Account deletion refused: RevenueCat is not configured");
    return { status: 503, body: { error: "subscription_cleanup_unavailable", retryable: true } };
  }

  try {
    await jobs.save(userID, { status: JobStatus.pending, last_error: null });
  } catch (error) {
    log.error("Account deletion job could not be recorded", error?.message ?? String(error));
    return { status: 500, body: { error: "deletion_failed", retryable: true } };
  }

  let first;
  try {
    first = await revenueCat(userID);
  } catch (error) {
    log.error("RevenueCat deletion failed", error?.message ?? String(error));
    await jobs.save(userID, { status: JobStatus.pending, last_error: describe(error) }).catch(() => {});
    return {
      status: 502,
      body: { error: "subscription_cleanup_failed", retryable: error?.retryable ?? true },
    };
  }

  const { error: authError } = await deleteAuthUser(userID);
  if (authError) {
    log.error("Account deletion failed", authError.message ?? String(authError));
    await jobs.save(userID, { status: JobStatus.pending, last_error: "auth_delete_failed" }).catch(() => {});
    return { status: 500, body: { error: "deletion_failed", retryable: true } };
  }

  let subscriptionRecord;
  let customerIDs = first.customerIDs;
  try {
    const sweep = await revenueCat(userID);
    customerIDs = [...new Set([...customerIDs, ...sweep.customerIDs])];
    subscriptionRecord = sweep.status === "queued" ? "pending_verification" : "deleted";
  } catch (error) {
    log.error("RevenueCat check after deletion failed", error?.message ?? String(error));
    subscriptionRecord = "pending_verification";
  }

  if (subscriptionRecord === "deleted") {
    await jobs.remove(userID).catch((error) => {
      log.error("Completed deletion job could not be removed", error?.message ?? String(error));
    });
  } else {
    await jobs.save(userID, {
      status: JobStatus.verifying,
      revenuecat_customer_ids: customerIDs,
      last_error: "unconfirmed",
    }).catch((error) => {
      log.error("Deletion job could not be updated", error?.message ?? String(error));
    });
  }

  const analytics = await requestAnalyticsDeletion(userID);

  return {
    status: 200,
    body: {
      deleted: true,
      analytics,
      subscriptionRecord,
      hadActiveSubscription: first.hadActiveSubscription || false,
    },
  };
}

/**
 * Retries RevenueCat deletion for accounts that are already gone. Called on a
 * schedule. Returns how many jobs were confirmed and how many remain.
 */
export async function sweepPendingDeletions({ jobs, revenueCat, log = console, maxAttempts = 50 }) {
  const due = await jobs.listVerifying(maxAttempts);
  let confirmed = 0;
  let remaining = 0;
  for (const job of due) {
    try {
      const result = await revenueCat(job.user_id);
      if (result.status === "queued") {
        remaining += 1;
        await jobs.save(job.user_id, { status: JobStatus.verifying, attempts: job.attempts + 1, last_error: "unconfirmed" });
      } else {
        confirmed += 1;
        await jobs.remove(job.user_id);
      }
    } catch (error) {
      remaining += 1;
      log.error("RevenueCat retry failed", error?.message ?? String(error));
      await jobs.save(job.user_id, {
        status: JobStatus.verifying,
        attempts: job.attempts + 1,
        last_error: describe(error),
      }).catch(() => {});
    }
  }
  return { confirmed, remaining };
}

function describe(error) {
  return String(error?.message ?? error).slice(0, 200);
}
