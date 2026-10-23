const appleReferenceOffset = 978307200;

export function endPayload(startedAt, plannedEndAt, now = Date.now()) {
  const seconds = Math.floor(now / 1000);
  const swiftDate = (value) => Date.parse(value) / 1000 - appleReferenceOffset;
  return { aps: {
    timestamp: seconds,
    event: "end",
    "dismissal-date": seconds - 1,
    "content-state": {
      startedAt: swiftDate(startedAt),
      plannedEndAt: swiftDate(plannedEndAt),
    },
  } };
}

export function deliveryStatus(httpStatus, attempts) {
  if (httpStatus === 200) return "sent";
  if ((httpStatus === 429 || httpStatus >= 500) && attempts < 5) return "pending";
  return "failed";
}
