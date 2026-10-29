# Flutter real estate sales — REST contract and workflow

Prepared 2026-10-07. Backend and dashboard implemented; Flutter screens must be added in the separately developed mobile app. Read MOBILE_BRD.md and MOBILE-API.md first. All paths here include `/api`; use bearer authentication and JSON. Backend source and integration tests are the contract evidence.

## 1. Business rules and access

- A closed deal means a **signed sale or lease contract**, confirmed by the project owner. Reservations and unsigned negotiations are not closed deals.
- HR/admin enables `salesEnabled` in the employee profile. Do not infer access from department names, job titles, or account roles. Existing employees default to disabled; disabling submission preserves their history and performance.
- Fetch `GET /api/sales/access`: `{ canSubmit, canReview, canSetTargets }`. Only an active linked sales-enabled employee can submit/edit their own activities. Targets are managed by HR/admin in the dashboard, not ordinary employee mobile screens.
- Current direct managers can review assigned employees' activities without receiving employee-directory, HR, or payroll permissions. HR/admin can review across departments. Nobody may verify their own activity, including HR and managers. The activity's returned `canReview` determines whether to offer review controls; the server rechecks it.
- Supported kinds: `meeting` (completed client meeting), `viewing` (completed property viewing), `closed-deal` (signed sale/lease). Do not register planned meetings as completed activities. Each viewing is one activity, not an additional duplicate meeting entry for the same event.
- Only `verified` entries count toward performance. `pending` and `returned` entries remain visible but do not count. Activity date controls the reporting month; submission/review timestamps are separate server-generated times. Activity dates must be between employment start and company `today`.
- Values mean **total signed contract value**, including the total contracted lease consideration for a lease. They are not deposits, company revenue, or commission. Currencies remain separate; no exchange rates or combined score are applied.
- One activity owner per contract in this release. Deal references are trimmed and case-insensitively unique across all employees/statuses. Shared agent attribution, commissions, pipeline, contract attachments and cancellation accounting are not implemented.

## 2. Screens

1. **Sales**: month selector, own verified meetings/viewings, sale/lease counts, contract values by currency, pending/returned counts, and monthly targets/achievement from the API.
2. **Register activity**: type-specific form below. Pre-fill date using company `today`; date-only values stay date-only.
3. **History/details**: filter by month, type and status; show client, project/compound, property/unit, purpose/outcome/follow-up or signed contract details, notes, submitted time, review reason/reviewer/time.
4. **Correct/resubmit**: own pending/returned entries only; use current revision and re-submit for verification. Verified entries require a manager/HR return for correction first.
5. **Team sales reviews**: available when `canReview`; use the server-scoped list and per-entry `canReview`. Verify pending activities or return pending/verified activities with a reason. Keep this separate from leave-request recommendations: sales verification is final for performance.

Hide registration/edit controls when `canSubmit` is false but allow own historical reads. Managers without personal sales access may still review their team. Never use `/employees` to build a mobile team selector: the authorized sales responses already contain employee names/numbers/departments.

## 3. Endpoints

| Method | Path | Response / access |
| --- | --- | --- |
| GET | `/api/sales/access` | Capability flags, all authenticated users |
| GET | `/api/sales/activities/me?month=2026-10` | Own activities; newest activity date/submission order first |
| GET | `/api/sales/activities?month=2026-10` | HR/admin or current direct manager's scoped activities, excluding a manager's own entries |
| GET | `/api/sales/activities/:id` | Accessible activity with current capability; inaccessible/missing returns 404 |
| POST | `/api/sales/activities` | HTTP 201 created or same-submission replay |
| PATCH | `/api/sales/activities/:id` | HTTP 200 corrected own pending/returned activity |
| PATCH | `/api/sales/activities/:id/review` | HTTP 200 verified/returned activity; authorized reviewer only |
| GET | `/api/sales/performance/me?month=2026-10` | Own monthly summary array, zero or one row |
| GET | `/api/sales/performance?month=2026-10` | HR/admin or direct manager's scoped summary array |

Activity lists also support `kind`, `status`, `employeeId`, and `department` query filters; all are optional, and filters cannot widen access. Team performance supports only `month`, `employeeId`, `department`. Own performance accepts only `month`. Month is mandatory, valid `YYYY-MM`. No pagination is present: these are monthly lists, not the full archive. Unknown query/body fields are rejected.

Dashboard-only endpoints: `POST /api/sales/targets` and `GET /api/sales/export?month=2026-10` (performance CSV; managers can export only their scoped team). Ordinary mobile employees must not expose target administration or export controls.

## 4. Activity payloads

Creation envelope: `{ "id": "client-generated UUID", "activity": { ... } }`. Generate and keep one UUID for the submission before sending. Ownership comes from the session; do not send employee ID, status, revision or review fields.

Client meeting:

```json
{
  "kind": "meeting",
  "activityDate": "2026-10-07",
  "clientName": "Example buyer",
  "projectName": "Example compound",
  "propertyReference": "",
  "purpose": "Discuss apartment requirements",
  "outcome": "Requested a property viewing",
  "followUpDate": "2026-10-09",
  "notes": "Interested in a three-bedroom unit"
}
```

Viewing uses the same fields with `kind: "viewing"` and a non-empty `propertyReference`, such as `Building A / Unit 12`. `followUpDate` may be null/omitted and cannot precede activity date.

Signed deal:

```json
{
  "kind": "closed-deal",
  "activityDate": "2026-10-07",
  "clientName": "Example buyer",
  "projectName": "Example compound",
  "propertyReference": "Building A / Unit 12",
  "dealReference": "SALE-2026-001",
  "transactionType": "sale",
  "value": 2500000.25,
  "currency": "EGP",
  "notes": "Sale contract signed"
}
```

`transactionType` is `sale` or `lease`. Value is a JSON number, positive, at most 1,000,000,000, with at most two decimal places. Currency is exactly three uppercase letters. Client/property/deal/purpose/outcome text is trimmed, required where shown, max 120 characters. Project and property are optional for meetings; project is optional for other kinds. Optional notes max 1000 characters; omitted project/property/notes become empty strings. Do not send meeting fields on a deal or monetary/deal fields on a meeting/viewing.

Correction envelope: `{ "expectedRevision": 3, "activity": { ...complete replacement payload... } }`. Result becomes pending, increments revision, and retains the previous review for context; earlier changes remain in audit history. Initial submission time is preserved, update time changes.

Review: `{ "expectedRevision": 1, "status": "verified", "reason": "Confirmed the signed contract" }`. Status is `verified` or `returned`; reason is 5–500 trimmed characters. Only pending entries can be verified. Pending or verified entries can be returned; returning a verified entry immediately removes its contribution from live performance. Already returned entries cannot be returned again without correction/resubmission.

## 5. Responses and performance

Activity responses contain the kind-specific fields plus `id`, `employeeId`, `employeeName`, `employeeNumber`, current `department`, `submittedAt`, `updatedAt`, integer `revision` (starts at 1), `status`, `canReview`, and `review` (null or `{ status, reason, by, byId, at }`). A pending corrected entry may retain a previous returned review; label it as a previous review, not its current approval.

Summary row fields:

- Employee context: `employeeId`, `employeeName`, `employeeNumber`, current `department`, `active`, `salesEnabled`, `month`.
- Verified totals: `meetings`, `viewings`, `meetingTotal` (sum of both), `deals`, `sales`, `leases`, and `transactionValues`, e.g. `{ "EGP": 2500000.25, "USD": 12000 }`.
- Unverified totals: `pending`, `returned`.
- `target`: null or `{ employeeId, month, meetings, deals, transactionValue, currency, revision, reason, updatedAt, updatedBy }`.
- `achievement`: `{ meetings, deals, transactionValue }` percentages, rounded to one decimal, allowed to exceed 100. A missing/zero count target or absent monetary target gives null, not zero performance. The meeting target includes both meetings and viewings. Monetary achievement counts only the target currency.

Display the returned totals; do not calculate a conversion rate or a combined performance score. Historical summaries are live: correction, verification, target edits, and employee department changes can affect a report generated later. Exports are snapshots, not frozen monthly approvals. Payroll and attendance do not change from sales activity.

## 6. Retry, concurrency and privacy

- A retry of POST with the same UUID/normalized payload returns the existing entry without counting/auditing it again. Reusing an ID for another employee or different payload returns 409. Duplicate contract references also return 409.
- After an uncertain creation response, GET by the saved submission UUID to reconcile. A genuine 404 allows retry with the **same UUID and payload**. Do not discard the UUID and create a fresh one automatically. If the employee wants to change data, reconcile first, then use PATCH on the existing entry or start a new submission only after confirming it was not saved.
- PATCH/review requires the exact current revision. On 409, refresh the record before retrying; never silently overwrite someone else's edit or review. A lost PATCH/review response also requires GET reconciliation.
- 400 means validation failure; 401 means sign in again; 403 means capability/assignment no longer allows the action; 404 means unavailable/not accessible; 409 means duplicate/stale state. Preserve forms on recoverable failures and refresh access after foreground return and 403.
- Keep client names, property details and contract amounts behind authenticated screens and out of logs/notifications/crash reports. Clear account state on logout. No GPS/background tracking or device permissions are needed for sales forms.

## 7. Mobile acceptance cases

| ID | Scenario |
| --- | --- |
| SALES-AC-01 | Sales-enabled employee can submit all three kinds; ordinary employees cannot submit; managers without personal sales access can review their authorized team |
| SALES-AC-02 | Activity appears with the same UUID, values, date and status in mobile and dashboard; server identifies the owner |
| SALES-AC-03 | Pending/returned entries do not count; verification updates own/team totals and targets; different currencies remain separate |
| SALES-AC-04 | Non-report/self review is denied; manager reassignment removes old access; hidden controls do not replace server authorization |
| SALES-AC-05 | Duplicate contract reference, stale revision and extra fields are rejected; timeout reconciliation does not duplicate an activity |
| SALES-AC-06 | Corrected pending/returned entry requires re-verification; verified entry needs reviewer return first; reasons/reviewer/history are visible |
| SALES-AC-07 | Company date bounds, follow-up ordering, unit references, positive money/precision and sale/lease wire values are validated |
| SALES-AC-08 | Month/type/status filters, loading/empty/retry states, disabled sales access, account switching and foreground refresh work against the real API |

Backend checks: `npm --prefix .\hr-backend run test:e2e`; isolated sales coverage is in `hr-backend/test/sales.e2e-spec.ts`. These checks do not replace Flutter analysis/widget/device tests and mobile-to-dashboard acceptance.
