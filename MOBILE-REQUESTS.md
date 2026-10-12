# Flutter employee requests — contract and workflow guide

Verified against backend source on 2026-10-12. Sections 1–9 own request-specific payloads, validation, response models, state transitions, and direct manager recommendations. Section 10 is the implementation request for the new real estate sales feature in the existing Flutter project.

Read [MOBILE-API.md](MOBILE-API.md) first for connection, bearer authentication, shared errors, attendance, and notifications. Read [MOBILE_BRD.md](MOBILE_BRD.md) for scope and acceptance. All paths here include `/api`; follow the base URL convention in MOBILE-API.md.

For the sales update, copy this file and MOBILE-API.md together. The complete sales REST contract and acceptance cases are included in MOBILE-API.md section 12; no separate sales document or backend source checkout is needed to implement it.

## 1. Endpoints and employee boundary

| Method | Path | Access / result |
| --- | --- | --- |
| POST | `/api/requests` | Active linked employee submits for self; HTTP 201 request object |
| GET | `/api/requests/me` | Own requests, newest submitted first; HTTP 200 array |
| PATCH | `/api/requests/:id/withdraw` | Own pending request only; HTTP 200 updated request |
| GET | `/api/requests/managed` | Server-authorized direct manager queue; HTTP 200 array |
| PATCH | `/api/requests/:id/manager-review` | Current assigned manager recommendation; HTTP 200 updated pending request |

These require bearer authentication. Submission identity comes from the session, never a client `employeeId`. Use UUID request IDs returned by the API. Send JSON and only allowed fields; DTOs reject extras. Optional fields may be omitted, not set to null unless supported.

There is no single-request GET, edit, employee reopen, request-types discovery, attachment upload/download, or leave-balance endpoint. Request lists support pagination and status filtering; filter by type locally. HR final decisions/reopening and manager assignment are dashboard workflows; employee mobile must not call them. Request detail navigation resolves IDs through own history or the authorized managed queue.

## 2. Request forms and submission bodies

### Type values

| Mobile label | Send as `type` | Form |
| --- | --- | --- |
| Normal vacation | `leave` | Full-day date range |
| Sick | `sick` | Full-day date range |
| Unpaid | `unpaid` | Full-day date range |
| Urgent | `urgent` | Full-day date range |
| Excuse | `excuse` | Date range, minutes, subtype, assigned shift |
| Mission | `mission` | Full-day date range |
| Personal holiday (existing compatibility type) | `holiday` | Full-day date range |
| Forgotten check-out | `forgotten-check-out` | Owned open attendance record and proposed departure |

Send lowercase API values, not display labels. There is no request-types endpoint; maintain this mapping in the client and preserve compatibility when displaying historical entries.

### POST /api/requests: full-day types

```json
{
  "type": "sick",
  "from": "2026-10-05",
  "to": "2026-10-06",
  "reason": "Medical appointment and recovery",
  "attachments": []
}
```

Same schema for `leave`, `sick`, `unpaid`, `urgent`, `mission`, and `holiday`:

- `from` and `to`: required real calendar dates, ordered `from <= to`, inclusive range of at most 93 days (`to - from <= 92 days`). `from` cannot be before `employee.startDate`.
- `reason`: required, trimmed, 5-500 characters. A mobile field labeled Description must still send `reason`.
- `attachments`: optional; shared attachment rules below.
- The backend does not restrict these ranges to future dates, working days, or a leave balance. Do not present those restrictions as implemented server validations.

### POST /api/requests: Excuse

```json
{
  "type": "excuse",
  "from": "2026-10-05",
  "to": "2026-10-05",
  "durationMinutes": 15,
  "excuseType": "leaving-early",
  "shiftId": "<assigned schedule UUID>",
  "reason": "Appointment",
  "attachments": []
}
```

- Date rules are the same as full-day requests, including the employment start date.
- `durationMinutes`: required JSON integer, 1-1440, and no longer than the selected shift length. For an overnight shift, compute duration across midnight. Send 15 for the screen label “15 M”; do not send a formatted duration string or decimal hours. A range carries one minutes value, not separately editable durations per date.
- `excuseType`: required, one of `leaving-early`, `arriving-late`, `during-shift`.
- `shiftId`: required existing schedule UUID that must equal the employee's current assigned `scheduleId`. Show the assigned shift name and times, not arbitrary schedule choices. Refresh profile/schedule if HR changed the assignment.
- `reason`: optional, trimmed, maximum 120 characters; omission defaults to an empty string. It is not required to have 5 characters for Excuse. Show the 120-character limit locally.
- The API stores the shift ID, not a shift-time snapshot; later schedule edits may change the times obtained from `/schedules`.
- Approval does not rewrite check-in/check-out, cancel lateness, add worked hours, or mark an entire day as leave.

### Attachments for full-day and Excuse requests

Attachments are **inline JSON base64**, not multipart uploads and not URLs:

```json
{
  "name": "medical-note.pdf",
  "mimeType": "application/pdf",
  "content": "<standard base64 file bytes>"
}
```

| Rule | Limit |
| --- | --- |
| Number of attachments | 0-3 |
| Decoded size per file | 1-524288 bytes (512 KiB maximum) |
| `name` | Required, trimmed, 1-200 characters |
| `mimeType` | `application/pdf`, `image/png`, or `image/jpeg` |
| `content` | Standard base64 with valid padding; 4-699052 characters; no data-URL prefix |

Check decoded file size before encoding and reject unsupported picker formats locally. Base64 increases payload size; the production server's JSON limit is 3 MiB. Attachments return inside request objects, including listings, so allow for larger responses. There is no separate request-attachment upload/download/delete endpoint. Decode returned bytes for private local viewing/sharing only at the user's action. The server validates the declared MIME type, base64 format, and size for these attachments; unlike attendance photos, request attachments are not decoded to verify actual file format.

### POST /api/requests: forgotten check-out

```json
{
  "type": "forgotten-check-out",
  "attendanceId": "<owned open attendance UUID>",
  "proposedCheckOut": "2026-10-05T15:00:00Z",
  "reason": "Forgot to check out when leaving"
}
```

Use an owned open record from attendance history. `attendanceId` is a UUID. Proposed departure must include UTC/offset, be at or after recorded check-in, and not be in the future. `reason` is required and trimmed, 5-500 characters. This type does not accept dates, shift/duration, or attachments. Missing/non-owned attendance returns 404; already closed attendance or a duplicate pending/approved correction request returns 409. Approval rechecks the current attendance record; it can fail if the record was closed meanwhile. Approval creates an audited attendance correction, not GPS/photo evidence.

### Overlap, duplicates, and submission recovery

- Pending and approved requests block overlapping date ranges, even across different full-day types and between full-day requests and Excuse.
- Two Excuse requests with overlapping dates conflict when both shift ID and excuse subtype match; different subtypes can coexist, but share the monthly minutes/request limit in section 4.
- Forgotten check-out conflicts only with another pending/approved forgotten check-out request for the same attendance record.
- Rejected and withdrawn requests permit a new submission subject to current validations. There is no request idempotency key. If POST times out, refresh `/api/requests/me` and reconcile before offering resubmission. A repeated identical pending/approved request normally returns 409 rather than replaying the original success.

### GET /api/requests/me and request response shape

Returns a page of own requests, newest first. `limit` defaults to 50 and accepts 1–100; optional `status` is `pending`, `approved`, `rejected`, or `withdrawn`. For the next page, send `before` equal to the last returned request ID and keep the same status filter. Continue until a page has fewer than `limit` items. There is no search, type filter, or individual-request GET endpoint; filter loaded items by type locally. Refresh from the first page after mutations.

A submission response and each list entry contain the submitted fields plus:

```json
{
  "id": "<request UUID>",
  "employeeId": "<employee UUID>",
  "employeeName": "Employee Name",
  "nationalId": "00123456789012",
  "status": "pending",
  "submittedAt": "2026-10-05T08:00:00.000Z",
  "decidedAt": null,
  "decidedBy": null,
  "decisionReason": null,
  "salaryDeductionDays": null,
  "attendance": null
}
```

`attendance` holds the original attendance snapshot for forgotten check-out, otherwise null. `decidedBy` is the reviewer's display name, not a UUID. `decidedAt` and `decisionReason` become populated after a decision. Reasons/attachments are employee-provided content; display as text or files, never execute as markup. Do not send server-managed identity, status, timestamps, deduction, or attendance fields back in a submission.

Current backend behavior for every non-forgotten-check-out type, including Excuse, sick, and mission: **final HR approval deducts 1 salary day; final rejection deducts 3 salary days, once per request regardless of dates or duration**. Pending/withdrawn requests and forgotten check-out have null deduction days. Historical decisions may also have null because deductions were not added retroactively. Display returned `salaryDeductionDays`, never infer an amount from duration or null. Explain current deduction behavior before submission; HR confirmation of this policy is an open release decision in the BRD. Employee accounts cannot fetch payroll reports.

Employees can withdraw their own pending requests but cannot edit them or give final decisions. HR can reopen eligible approved requests as described below; rejected and withdrawn requests remain final. Approved full-day requests affect missing scheduled HR report rows without replacing existing attendance; they do not create check-in records in `/attendance/me`. Approval of Excuse leaves attendance unchanged.


## 3. Response model and Flutter details

The request object combines its type-specific submitted fields with these server-managed fields:

| Field | Model behavior |
| --- | --- |
| `id`, `employeeId` | UUID strings; keep separate from user ID |
| `employeeName`, `nationalId` | Submission identity snapshot; national ID remains text |
| `status` | `pending`, `approved`, `rejected`, `withdrawn` |
| `submittedAt` | ISO timestamp |
| `decidedAt`, `decidedBy`, `decisionReason` | Nullable; final reviewer is a display name |
| `salaryDeductionDays` | Nullable number; use the returned value |
| `attendance` | Original attendance snapshot for forgotten check-out, otherwise null |
| `managerStage` | Optional `not-required`, `pending`, `approved`, `rejected`; separate from overall status |
| `managerEmployeeId`, `managerDepartment` | Optional current routing fields; manager ID may be null |
| `managerReview` | Optional/null object: `status`, reviewer `employeeId`, `department`, `reviewedBy`, `reviewedAt`, `reason` |
| `lastChange` | Optional object: `action` (`withdraw`/`reopen`), `reason`, `at`, actor display name `by` |

Historical records may omit workflow fields. Preserve absence rather than inventing manager approval. For a pending record, use `managerStage` to decide whether the recommendation is current; a stored recommendation must not override current server routing. Request attachments, if present, contain inline base64 in list responses.

Implement separate Dart submission variants for date-range, Excuse, and forgotten check-out so incompatible fields cannot leak into strict DTOs. A request response model additionally reads all workflow fields above. Keep a safe display fallback for unknown future types/statuses and disable unsupported mutations. Display dates as calendar dates, timestamps in the company timezone, and forgotten departure using the attendance snapshot's timezone.

Request details show submitted type/dates/minutes/reason/attachments, overall status, manager stage and valid recommendation, HR decision/reason/time, returned deduction days, and latest withdrawal/reopen information. Show the server's employee identity only in authorized manager details. Do not expose a full employee directory to populate these screens.

## 4. Overlap and monthly Excuse allowance

Pending and approved requests reserve their dates/attendance reference; rejected and withdrawn requests do not.

- Overlapping full-day requests conflict, including different types. Full-day/Excuse overlap also conflicts.
- Two overlapping Excuses conflict when both shift ID and subtype match. Different subtypes may coexist but share the monthly allowance.
- Forgotten check-out requests conflict only with pending/approved forgotten check-out requests for the same attendance ID, not with time-off ranges.

Excuse has a shared limit of **240 minutes and at most 3 pending/approved requests per requested calendar month** across all subtypes. Exactly 240 minutes and 3 requests are allowed. `durationMinutes` is charged for every date, including non-working dates in the requested range. A cross-month request counts once in each affected month; minutes split according to dates.

Example: 60 minutes per day from October 31 through November 2 reserves 60 minutes/one request in October and 120 minutes/one request in November. Rejection or withdrawal releases the reservation. Manager rejection alone keeps the overall request pending and does not release it. Approval rechecks allowance excluding the request itself.

The server returns 409 on overlap or exceeded allowance without creating a request. A mobile estimate from refreshed own history is advisory; there is no balance API, and concurrent changes can invalidate the estimate.

## 5. Withdrawal, correction, and status transitions

Withdraw with `PATCH /api/requests/:id/withdraw`:

```json
{ "reason": "No longer needed" }
```

Reason is trimmed, 5–500 characters; no extra fields. The ID must be a UUID. Only the owner of a pending request may withdraw, including a forgotten check-out request or a request already recommended by a manager but still awaiting HR.

| Transition | Actor / effect |
| --- | --- |
| New → pending | Employee submission; reserves dates/Excuse allowance |
| Pending → pending with manager stage approved/rejected | Assigned manager recommendation; no final deduction or attendance change |
| Pending → withdrawn | Requesting employee; releases reservations, clears decision/deduction, keeps history |
| Pending → approved/rejected | HR final decision in dashboard; returned deduction/attendance effects apply |
| Approved non-forgotten-check-out → pending | HR reopen in dashboard, if eligible/unlocked; clears decision/deduction and manager recommendation, retains/rechecks reservations |

For correction, withdraw a pending request and submit a replacement. There is no edit-in-place endpoint. Rejected/withdrawn requests can be replaced with a new submission if validations permit, but cannot be reopened. An approved request needs HR handling; show contact-HR guidance rather than employee reopen controls.

HR cannot reopen their own request, an approved forgotten check-out, or a request included in locked payroll. Forgotten check-out already approved is handled via HR attendance correction. Mobile displays subsequent API state; it does not recalculate approved payroll or promise reversal of exported reports/payments.

Withdrawal returns updated `status: "withdrawn"`, null decision/deduction fields, and `lastChange`. Invalid input is 400, wrong owner 403, missing request 404, and non-pending state 409. Refresh own history, managed queue if relevant, attendance where relevant, and notifications after mutations.

## 6. Assigned direct manager recommendations

HR assigns managers through the dashboard. Assignment does not change the employee role or grant HR/payroll/directory/correction access. Mobile must not use `/departments` to discover managers; that endpoint requires HR access.

`GET /api/requests/managed` returns pages of authorized pending requests, newest first, including already-recommended requests awaiting HR. It uses the same `limit`/`before` pagination; a `status` filter other than `pending` returns an empty array. Own requests are excluded. No assignment/no linked employee returns an empty array. An empty queue cannot distinguish an unassigned employee from a manager without pending work; use an empty-state message rather than asserting a role.

Offer recommendation controls only for a server-returned managed item with overall `status: "pending"` and `managerStage: "pending"`. Submit:

```json
{ "status": "approved", "reason": "Department coverage is arranged" }
```

Use `PATCH /api/requests/:id/manager-review`; `status` is `approved` or `rejected` and reason is trimmed, 5–500 characters. Response remains overall pending, with the recommendation in `managerReview` and updated `managerStage`. Label actions “Recommend approval” / “Recommend rejection” and explain that HR decides finally.

Wrong manager/self-review is 403; repeated recommendation or invalid stage is 409; missing request is 404. Refresh current queue after success, foreground return, or conflicts. HR must wait for the recommendation when required and may disagree. The recommending manager cannot also make that request's final HR decision. No manager/self-request or no assignment routes directly to HR. Assignment/department changes and HR reopening may reset recommendations; current server fields govern action availability.

## 7. Notifications, failures, and refresh

Notification transport/read state is defined in [MOBILE-API.md](MOBILE-API.md). Requesting employees receive `request-decided`, `request-reopened`, and `manager-reviewed`; managers receive `manager-review-required`. When the manager taps one, refresh and page through the managed queue to find its `requestId`, then open its details in a bottom sheet. Show recommendation actions only while its current `managerStage` is `pending`; require a reason and refresh the queue/inbox after submission. Marking the notification read does not submit a recommendation. Route other IDs by refreshing and paging through own history or the managed queue; do not invent a single-request GET. A notification may no longer describe current status.

Disable duplicate taps during POST/PATCH and preserve unsent form input in memory after recoverable errors. Request creation has no idempotency key: after timeout, refresh history and compare the candidate's submitted fields/time before manual retry. Do not auto-repeat POST or assume overlap protection is a general deduplication guarantee. Withdraw/review outcomes may also be uncertain; refresh the item/queue before retrying. Offline submissions are not queued in this release.

400 means validation; 401 normally requires sign-in; 403 means restricted access; 404 means unavailable item; 409 means overlap/allowance/state conflict. Normalize safe server messages; transport failures may lack JSON. Attendance approval conflicts are for HR to resolve, not for mobile to bypass. See the shared error guide for 413, 429, and server/network failures.

## 8. Request acceptance checklist

- Every type serializes exactly its allowed fields; all eight types render in history.
- Date-only ranges remain unchanged across device timezones; 93-day/start-date limits work. Forgotten check-out uses an owned open record and a past timestamp at or after check-in.
- Excuse sends integer minutes/current assigned shift and optional 120-character reason; no general 5-character requirement is imposed on Excuse.
- Attachment count/MIME/base64/decoded-size constraints work; files remain private. Forgotten check-out cannot include attachments.
- Overlap rules and exact monthly boundaries work, including cross-month allocation and rejection/withdrawal release.
- Pending withdrawal works; final/withdrawn items have no withdrawal control; HR reopen/reset is reflected after refresh.
- Manager recommendation cannot be mistaken for final approval, cannot affect attendance/deductions, and cannot review self or another department.
- Details handle nullable deductions and missing historical manager fields; server changes refresh across foreground return and notification navigation.
- Lost-response handling does not auto-create duplicates; no fake/offline success appears.
- Approved forgotten check-out matches HR's corrected attendance; full-day approvals affect missing report rows while Excuse leaves attendance unchanged.

Use the full acceptance scenarios in [MOBILE_BRD.md](MOBILE_BRD.md) and isolated backend accounts/databases. Verify real REST responses, not only mocked Flutter models.

## 9. Source references

- [Routes and access entry points](hr-backend/src/requests/requests.controller.ts).
- [Submission/review/withdrawal schemas](hr-backend/src/requests/dto/request.dto.ts).
- [Response shape](hr-backend/src/requests/types/employee-request.type.ts).
- [Overlap, allowance, workflow, corrections, and deductions](hr-backend/src/requests/requests.service.ts).
- [Payroll lock restrictions](hr-backend/src/payroll/payroll-lock.ts).
- [REST integration regression tests](hr-backend/test/hr.e2e-spec.ts).

Recheck these sources when backend behavior changes; source inspection does not authorize mobile imports or database access. Update request-specific details here and shared integration behavior in MOBILE-API.md.

## 10. Implementation request: real estate sales in the existing mobile app

Implement the following additive feature using the existing Flutter architecture, API client, authentication, navigation, and form components. The backend and admin dashboard already support it. Use MOBILE-API.md section 12 as the wire contract. Do not rebuild the app or change existing attendance, leave requests, or notification behavior.

### Business baseline

Employees record completed client meetings, completed property viewings, and closed deals. A closed deal means a **signed sale or lease contract**, not a reservation, negotiation, or payment receipt. Each viewing is one activity; do not automatically create a second meeting. Contract value is the total signed value, including total contracted lease consideration, not commission or deposit. Only manager/HR-verified activities count toward performance.

### Required edits

1. **Models and API calls.** Add `salesEnabled` to the employee model, capability flags, separate type-specific activity submission models, activity responses with revision/review metadata, and monthly performance/target response models. Implement the nine mobile sales endpoints listed in MOBILE-API.md. Use JSON and bearer authentication; ownership comes from the session. Do not serialize response metadata into submission bodies.
2. **Access and navigation.** Fetch `/api/sales/access` after session validation and on foreground return. Show a Sales area for linked employees with their historical reads even if submission is disabled. Show Register/Correct only when `canSubmit`. Show Team sales reviews only when `canReview`, including managers whose personal sales submission is disabled. Refresh access after 403. Never infer capabilities from department names or fetch `/employees` or `/departments`.
3. **Own Sales summary.** Default the reporting month from company `today`, with a month selector. Fetch own performance and history. Show verified meetings, viewings, their combined total, signed sales/leases, separate contract totals per currency, pending/returned counts, and the API's monthly targets/achievement. Display missing targets as “Not set”; display null achievement as unavailable, rather than zero. Percentages may exceed 100. No combined performance score or currency conversion.
4. **Register activity form.** Use company `today` as the default activity date. Meeting fields: date, client, optional project/compound and property/unit, required purpose and outcome, optional follow-up and notes. Viewing uses the same fields with a required property/unit. Signed deal fields: date, client, optional project/compound, required property/unit, unique contract reference, sale/lease choice, positive two-decimal contract value and uppercase three-letter currency, optional notes. Remove fields belonging to the previous type when switching forms; send only the selected type's schema. Apply the documented bounds and preserve date-only strings.
5. **History and details.** Provide month/type/status filters using the REST query contract. Show activity date separately from server submission time, client/project/unit details, signed contract details or meeting outcome/follow-up, status text, reviewer/reason/time, and previous review context on corrected pending entries. These are monthly lists without pagination. Do not invent an activity deletion endpoint or full review-history endpoint.
6. **Correct and resubmit.** Offer editing only for owned pending/returned entries with current submission access. Send the complete type-specific replacement plus `expectedRevision`. Correction returns the entry to pending. Verified entries are read-only until a reviewer returns them. Reload history and performance after success.
7. **Team verification.** Fetch server-scoped team activities and performance; derive employee choices from these returned records. Offer Verify only on pending entries and Return on pending/verified entries when the item's `canReview` permits it. Require a 5–500 character reason and current `expectedRevision`. Exclude self-review controls. Sales verification is final for performance; keep it separate from leave-request “Recommend approval/rejection”. Returning a verified entry removes its counted contribution immediately.
8. **Submission safety.** Generate one UUID before creation and keep it with the exact submitted payload during uncertain outcomes. On timeout, reconcile through `GET /api/sales/activities/:id`; a genuine 404 allows retry with the same UUID/payload. Do not generate another ID for an automatic retry. After uncertain PATCH/review or a stale-revision 409, GET the activity and reconcile before retrying. Keep forms on recoverable failures, disable duplicate taps, and never display offline success or queue writes for later.
9. **Lifecycle and privacy.** Refresh affected activity, summary and access data after mutations and foreground return. Protect against old-account/in-flight responses repopulating state after account changes. Clear client/property/contract data and unresolved submissions on logout/account switch; keep these values out of logs and crash reports. Sales requires no location/camera permissions. The backend does not currently emit sales notifications; use explicit refresh, without inventing push or notification types.

Targets and CSV exports stay in the dashboard. Do not add mobile target administration, contract attachments, deal cancellation, shared agent attribution, commissions, pipeline stages, background tracking, or payroll calculations.

### Completion and verification

Run Flutter analysis and the project's existing tests. Add focused model/form/retry checks using the existing test tools, then verify SALES-AC-01–08 from MOBILE-API.md against isolated accounts and the actual REST backend. At minimum demonstrate: meeting/viewing/sale/lease submission; pending excluded from totals; dashboard verification reflected in mobile; returned correction and re-verification; duplicate contract and stale revision errors; same-UUID timeout reconciliation; self/outside-team review denied; company/device timezone differences; disabled submission with history retained; account isolation.

Record changed files, checks run, API environment configuration, and any device/backend access that prevented acceptance. Mock-only tests do not complete the REST integration. Preserve the current mobile project's platform/language choices and existing functionality.
