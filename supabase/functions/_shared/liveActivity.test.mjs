import assert from "node:assert/strict";
import test from "node:test";
import { deliveryStatus, endPayload } from "./liveActivity.mjs";

test("end payload uses ActivityKit's default Date encoding and immediate dismissal", () => {
  const payload = endPayload(
    "2001-01-01T00:00:00.000Z",
    "2001-01-01T01:00:00.000Z",
    Date.parse("2001-01-01T01:00:10.000Z"),
  );
  assert.equal(payload.aps.event, "end");
  assert.equal(payload.aps["content-state"].startedAt, 0);
  assert.equal(payload.aps["content-state"].plannedEndAt, 3600);
  assert.ok(payload.aps["dismissal-date"] < payload.aps.timestamp);
});

test("only transient APNs failures retry, and retries stop", () => {
  assert.equal(deliveryStatus(200, 1), "sent");
  assert.equal(deliveryStatus(500, 1), "pending");
  assert.equal(deliveryStatus(429, 4), "pending");
  assert.equal(deliveryStatus(500, 5), "failed");
  assert.equal(deliveryStatus(400, 1), "failed");
});
