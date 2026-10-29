# Attendance location monitoring — Flutter handoff

Approved on 2026-10-12: monitor location while attendance is open, using a **150-metre radius from the office coordinates**. Missing location never forces checkout or creates a deduction. The Flutter project is developed separately and is not present in this workspace. Backend support alone does not enable phone tracking.

Company Settings now controls the office coordinates, manual attendance radius, warning/automatic checkout radius, and time to return. The 150-metre boundary and 300-second grace period below are defaults. Always load `tracking.radiusMeters` and `tracking.graceSeconds` from the policy API; do not hard-code these values in warnings. Fresh location updates use the current radius. New warnings use the current grace period; existing persisted `returnBy` deadlines remain unchanged by settings edits.

## REST contract

Use authenticated REST only. `GET /api/attendance/policy` now includes `tracking`:

```json
{
  "radiusMeters": 150,
  "graceSeconds": 300,
  "updateIntervalSeconds": 30,
  "staleAfterSeconds": 90,
  "maxCaptureAgeSeconds": 60,
  "maxAccuracyMeters": 50,
  "confirmationSeconds": 15
}
```

Default office coordinates are latitude 30.023092, longitude 31.528179; use the current top-level latitude and longitude from the policy API. The existing top-level `radiusMeters: 50` still governs manual check-in/check-out with GPS and a photo; `tracking.radiusMeters: 150` governs departure monitoring. No photo is required for a location update or automatic checkout.

`POST /api/attendance/:id/location` accepts JSON for the exact owned, open attendance record:

```json
{
  "available": true,
  "latitude": 30.026,
  "longitude": 31.528179,
  "accuracyMeters": 10,
  "capturedAt": "2026-10-12T08:00:00Z"
}
```

When permissions are denied, services are disabled, or a fresh fix cannot be obtained, send only:

```json
{ "available": false }
```

The server returns HTTP 201 and the location state:

```json
{
  "status": "outside",
  "lastCapturedAt": "2026-10-12T08:00:00.000Z",
  "outsideSince": "2026-10-12T07:59:30.000Z",
  "returnBy": "2026-10-12T08:05:00.000Z",
  "distanceMeters": 323.1,
  "accuracyMeters": 10,
  "autoCheckedOutAt": null
}
```

`GET /api/attendance/me` records and authorized attendance report rows include `location` with this same shape, or null for records without monitoring. Status is `inside`, `outside`, `unavailable`, or `auto-checked-out`; normal attendance `status` is unchanged. HR/manager tables display the location state and return deadline. CSV exports include location status and deadline. Actor identity is server-owned and never returned in location state.

## Rules and safety

- The server requires fresh, increasing capture timestamps; future, stale, or repeated/out-of-order updates return 409. Invalid bodies return 400, unauthorized sessions 401, another employee's/missing record 404, and closed attendance 409.
- Accuracy must be positive. Accuracy above 50 metres marks location unavailable. A reading is definitely outside only when `distance - accuracy > tracking.radiusMeters`; definitely inside when `distance + accuracy <= tracking.radiusMeters`. A reading whose accuracy overlaps the boundary marks location unavailable and cancels the countdown.
- Two reliable outside readings, received at least 15 seconds apart, confirm departure. The second starts a return window of `tracking.graceSeconds` seconds (default five minutes). Subsequent reliable outside readings preserve the deadline. This five-minute duration and checkout-at-expiry are initial implementation defaults.
- Reliable return inside cancels the countdown. Explicit unavailability or more than 90 seconds without a fresh capture also cancels it, leaving attendance open. Recovery starts a new departure confirmation and full grace period; it never resumes an expired countdown.
- A backend worker checks every ten seconds. Checkout is saved at the persisted deadline only if outside evidence is still fresh. Deadline and state survive restarts; an outage that leaves location stale cancels the countdown on recovery. A late worker runs only with fresh evidence. Each automatic checkout is audited once as `attendance.auto_checked_out`; no photo is fabricated and no payroll deduction is created.
- Normal checkout and HR corrections clear active monitoring. The existing one-interval-per-workday rule remains: automatic checkout does not allow another check-in that day. HR can review/correct mistakes using the existing audited correction flow. Break/mission exemptions are not implemented.
- GPS is supplied by the phone and is not spoof-proof. A missing network, session expiry, dead phone, OS suspension, or stopped app results in unavailable location once evidence becomes stale.

## Flutter implementation checklist

1. Configure Android/iOS background location permissions and platform lifecycle support for the actual supported versions. Explain tracking before permission requests; monitor only open attendance, never before check-in or after checkout. Android/iOS require device-specific implementation and real-device tests.
2. Read policy and own attendance on launch/sign-in/resume. Start monitoring the returned open record; stop on confirmed manual/automatic checkout, logout, account switch, or 401.
3. Aim to send a new fix every 30 seconds while checked in, including when stationary. Send capture time, not upload time. Do not replay queued old coordinates or invent current coordinates from cached data. Serialize requests to preserve order. Background timing is best effort; never claim uninterrupted tracking.
4. If a fresh fix is unavailable, send `{ "available": false }` when connected. If reporting itself fails, explain the connection problem; the server independently marks stale location unavailable. Do not force checkout locally.
5. Display the server's `returnBy` countdown and a visible warning/local notification: “You are outside the office. Return before [time] to avoid automatic checkout.” A null deadline means there is no active return timer. Reconcile 409 via `GET /api/attendance/me` instead of blindly retrying.
6. Display unavailable location distinctly: “Location unavailable. Attendance remains open. Restore location access or contact HR.” Refresh the server state after every update and on resume; refresh attendance when the deadline passes to learn whether checkout occurred. Server deadlines are authoritative; device time only renders the countdown.
7. Collect no off-duty movement history. Backend storage retains the latest distance/accuracy/capture time and deadline, not a route of coordinates. Existing event evidence and automatic-checkout audit remain private. Redact locations/tokens from logs.

## Acceptance

- Real-device foreground/background reports match the same record visible to HR, and tracking stops after checkout/account change.
- One outside reading cannot start a countdown; a confirmed departure starts five minutes. Reliable return cancels it.
- Fresh outside reports through expiry produce exactly one checkout at the deadline with an audit; no camera evidence or payroll deduction is fabricated.
- Explicit unavailability, poor accuracy, boundary uncertainty, and missing reports through expiry leave attendance open, mark unavailable, and create no deduction.
- Recovery/restart preserves a still-valid deadline, but stale coverage starts a new confirmation rather than penalizing the employee.
- Wrong ownership, malformed coordinates, stale/future/replayed capture times, and updates for closed records are rejected.

Backend REST integration tests cover the state transitions and access rules. Flutter analysis/widget tests and an Android/iOS background-permission, battery, network, and clock pilot remain required in the separate mobile project.
