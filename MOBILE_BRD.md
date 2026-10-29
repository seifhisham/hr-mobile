# Employee Mobile Application — Business Requirements Document

Branch contract update (15 October 2026): employees attend only their assigned branch. Fetch `/api/attendance/policy` before capture; the server resolves the assigned/saved workday policy, including overnight transfers. Do not offer an attendance branch picker or trust a client-supplied branch ID. Existing personal REST endpoints remain; attendance responses add branchId/branchName and `/api/auth/me` adds workspace/company status and HR grant IDs. Clear sensitive cached data on sign-out or revoked access.

Version: 1.3 | Updated: 2026-10-12 | Status: implementation baseline; open business decisions require confirmation before release.

## 1. Purpose and outcome

Build the Flutter employee application for the existing Company HR system. Employees must be able to sign in, record attendance with live office evidence, view their own attendance, submit and track requests, receive in-app notifications, and manage their password. Employees with the manager role also need direct-report request recommendations and team attendance and sales views.

Success means mobile actions produce the same backend records visible to HR in the existing dashboard, with server-enforced identity, permissions, attendance rules, and request state transitions.

This document governs mobile scope and acceptance. [BRD.md](BRD.md) remains the overall business requirements document. [hr-backend/API.md](hr-backend/API.md) describes the REST contract. Backend controllers, DTOs, services, and tests are the evidence for current behavior; reconcile discrepancies before implementation rather than inventing a contract.

## 2. Instructions for the implementing AI

1. Read this document, root `AGENTS.md`, `README.md`, and `hr-backend/API.md` before building or changing mobile features. Read any instructions in the mobile directory when it exists.
2. Inspect the relevant REST controller, DTO, response type, and service for each feature. Define mobile models from actual JSON responses and verify them through REST integration tests.
3. Implement in the delivery order in section 12. A feature is complete only when its acceptance cases pass against the backend and its loading, empty, permission-denied, and failure states work.
4. All mobile/backend communication must use the REST API. Backend source inspection is permitted for understanding contracts; mobile runtime code must never import backend modules, access SQLite, or call backend services directly.
5. Keep authentication, authorization, timestamps, workday assignment, attendance calculation, deductions, and request decisions authoritative on the server. Client validation assists employees; it does not replace server validation.
6. Use current API capabilities. Record a missing capability as a backend dependency with its proposed contract and acceptance case. Do not silently build fake success states, new business rules, or privileged workarounds.
7. Keep changes within employee mobile scope. Backend changes that alter company policy or existing workflows require an explicit scope decision.
8. Document setup, API base URL configuration, supported devices, permissions, and verification commands when the mobile project is created. Never copy real credentials or company records into examples or fixtures.

### Contract discrepancies already identified

- Early API guide text lists only leave, holiday, and forgotten check-out and says cancellation/notifications are excluded. Current source and later guide sections also support additional request types, pending withdrawal, notifications, and manager review.
- General request reasons are 5–500 trimmed characters, but Excuse reasons are optional, default to an empty string, and have a 120-character maximum.
- Current request decisions assign 1 deduction day on approval and 3 on rejection to **every request type except forgotten check-out**, including Excuse, sick, unpaid, urgent, and mission. This is current backend behavior, not a newly approved mobile policy. Display returned `salaryDeductionDays`; obtain HR confirmation before release if the policy needs correction.
- The attendance policy response exposes coordinates, radius, accuracy, capture age, bytes, and formats. It does not expose the implementation's 20-megapixel image limit or 10-second future clock tolerance. Treat these as current server constraints and recheck them when implementing capture.

## 3. Users and access boundary

| User | Mobile access |
| --- | --- |
| Active employee with an account and linked profile | Own profile, attendance, requests, notifications, and password actions |
| Direct manager | Employee features plus server-returned direct reports, managed requests, recommendations, attendance, and sales views |
| HR/admin account with a linked employee profile | May use the same personal employee workflows; privileged administration remains in the dashboard |
| Account without an employee profile | Explain that employee access is unavailable and provide sign-out/support guidance |
| Inactive employee or expired/revoked session | Return to sign-in when the API rejects authentication |

The manager role and direct assignments do not grant employee-directory, payroll, attendance-correction, or final HR-decision access. Never infer manager privileges from department name or job title. `/requests/managed` is the authorized queue; an empty list means no current accessible work, not proof that the user is not a manager.

HR provisions accounts and resets forgotten passwords. There is no employee registration or self-service password recovery API.

## 4. Scope and screen map

| Screen | Required content and actions |
| --- | --- |
| Sign-in | Email/password, show/hide password, submit state, useful authentication errors, contact-HR guidance |
| Home | Employee name/number, company name, assigned schedule, backend workday, current attendance, check-in/check-out action, unresolved open record guidance, unread notifications |
| Attendance | Own recorded intervals, local filtering of returned records, record details, stored timezone, timestamps/status, available evidence, forgotten check-out entry point |
| Requests | Own request history and filters for pending/approved/rejected/withdrawn; create, view details, withdraw eligible requests |
| New request | Type-specific fields, validation, optional supported attachments, submission confirmation |
| Request details | Submitted data, overall status, manager stage/recommendation, final HR decision/reason/time, returned deduction days, withdrawal/reopening history |
| Notifications | Inbox, unread count/filter, mark read, route to current request or accessible record |
| Profile/account | Read-only employee details and assigned schedule, change password, sign out |
| Department reviews | Managed queue, request details, approve/reject recommendation with reason; actions only when server stage permits |
| Sales | Own real estate activity history, completed client meetings/property viewings, signed sale/lease submission, corrections, monthly verified totals and targets |
| Team sales reviews | Current direct manager's authorized sales activities, verification/return with reasons; self-review forbidden |

Use simple employee navigation: Home, Attendance, Requests, and Account, with a notification bell and Department reviews entry. Refresh the managed queue when opened and after recommendations. This is a proposed navigation structure, not a requirement for a particular UI library.

Out of scope: HR/admin dashboard replacement, employee creation/editing, schedule/settings administration, final request decisions, request reopening by employees, manual attendance corrections, payroll/payslips/bank payments, company-wide holiday administration, leave entitlement balances, public registration, background push/email/SMS, offline attendance synchronization, off-duty GPS tracking, facial recognition, and multiple attendance intervals per workday.

### LOCATION — Attendance monitoring (approved additive scope, 2026-10-12)

Implement [MOBILE-LOCATION.md](MOBILE-LOCATION.md): background location reporting only while attendance is open, a 150-metre departure boundary from the office point, and a server-owned five-minute return window after reliable departure confirmation. Missing, stale, inaccurate, or uncertain location marks location unavailable and cancels the return timer; it must never force checkout or create a deduction. Reliable return cancels the timer. Fresh outside evidence through expiry permits an audited automatic checkout. Read the handoff for REST bodies, state responses, platform lifecycle requirements, defaults, and acceptance cases. The separately developed Flutter project must implement reporting and warnings before this feature works on phones.

- LOC-01: Load `policy.tracking` and start/resume monitoring the exact owned open attendance record after sign-in, launch/resume, or successful check-in. Monitor only open attendance; stop after confirmed checkout, logout, account switch, or 401. Configure background permissions/lifecycle for supported Android/iOS versions and explain tracking before requesting access.
- LOC-02: Aim to report a fresh fix every 30 seconds, including when stationary, using `POST /attendance/:id/location`. Send actual capture time, serialize requests, and never replay queued old fixes. Phone background timing is best effort; never promise uninterrupted tracking.
- LOC-03: The departure radius is company-configurable (default 150 metres) from the saved office coordinates, separate from the configurable manual capture radius (default 50 metres). Load the current radii from the policy API. Server confirmation requires two reliable outside readings at least 15 seconds apart; the second starts the company-configured return window (`policy.tracking.graceSeconds`, default five minutes). Existing warning deadlines remain unchanged when company settings are edited. The server uses reported accuracy to distinguish inside, outside, and uncertain readings.
- LOC-04: Display the server's `returnBy` countdown and a clear warning/local notification. Returning reliably inside cancels the countdown. Only the backend may automatically close attendance, at the saved deadline with fresh outside evidence and an audit. Refresh own attendance at expiry rather than claiming local checkout success.
- LOC-05: Send only `{ "available": false }` when fresh location cannot be obtained and connectivity permits. More than 90 seconds without a fresh capture, accuracy above 50 metres, or uncertainty at the boundary also marks location unavailable and cancels the countdown. Show “Location unavailable. Attendance remains open.” with recovery guidance. Never deduct or check out because reporting stopped; recovery requires new departure confirmation and a full return window.
- LOC-06: Reconcile 409 through own attendance; handle capture timestamps that are stale, future, or out of order. Keep unavailable-location state separate from normal attendance status. Automatic checkout requires no photo and retains the one-interval-per-workday rule. Break/mission exemptions are not implemented. Existing audited HR corrections remain the recovery path for mistakes.

## 5. Functional requirements

### SALES — Real estate activities and performance

Sales is an approved additive scope. Implement [MOBILE-SALES.md](MOBILE-SALES.md), which defines the REST payloads, capability checks, state transitions and SALES-AC-01–08. A closed deal means a signed sale or lease contract, confirmed by the project owner. HR/admin explicitly enables sales submission per employee. Count only verified activities; display separate meeting/viewing, sale/lease and per-currency contract-value totals and independent monthly targets. Current direct managers verify assigned employees' activities; HR/admin can also review. No self-verification, combined score, commission/payroll calculation, or full CRM is introduced. The backend/dashboard are implemented; mobile delivery remains to be completed in the separately developed Flutter project.

### AUTH — Authentication and account

- AUTH-01: Sign in with `POST /auth/login` using email/password. Retain the returned opaque token in platform secure storage and send `Authorization: Bearer <token>` on protected requests. Store no password.
- AUTH-02: On startup with a stored token, validate using `GET /auth/me`; load employee, company timezone/name, and company `today`. Network unavailability must show a connection problem rather than claiming the account is invalid.
- AUTH-03: Sessions currently expire after 12 hours; no refresh-token endpoint exists. On protected-request 401, clear local session/personal state and return to sign-in. Avoid a retry loop.
- AUTH-04: Change password with current/new password, minimum 8 characters for the new password. Successful change revokes all sessions; clear local credentials and require sign-in again.
- AUTH-05: Sign out through `POST /auth/logout` and clear secure token, personal state, and temporary evidence. If the network fails, clear local access and explain that server revocation could not be confirmed; do not claim it succeeded remotely.
- AUTH-06: Show the server's authentication error safely. Five failed logins for an email cause a 15-minute lockout (429); explain waiting or contacting HR.
- AUTH-07: Display profile fields from the API without allowing edits. Keep `id`, `employeeNumber`, and `nationalId` distinct. National ID is text and must preserve leading zeros; avoid placing it prominently on Home.

### ATT — Attendance and capture

- ATT-01: Load `GET /attendance/me` and `GET /attendance/policy`. Use returned `workDate` for attendance; it can differ from company calendar `today` for overnight shifts. Assigned schedule is read-only.
- ATT-02: Fetch current policy rather than embedding office settings as the mobile source of truth. Current office is latitude 30.023092, longitude 31.528179; radius 50 metres, positive accuracy at most 50 metres, and capture age at most 120 seconds. Accuracy does not expand the permitted radius.
- ATT-03: Request foreground location and camera access when needed, with a short explanation. Handle denial, permanent denial, disabled location services, unavailable camera, and insufficient accuracy with recovery guidance. Capture a fresh camera image of the place and current GPS for **each manual** check-in/check-out. Attendance evidence must not come from gallery selection or an old capture. Automatic location checkout follows LOC-04 without a photo.
- ATT-04: Submit multipart with exactly `latitude`, `longitude`, `accuracyMeters`, `capturedAt`, and one binary `photo`. Text fields are strings; `capturedAt` is ISO 8601 UTC or explicit offset. Let the HTTP library generate the multipart boundary. Employee identity and attendance timestamps are never supplied in these bodies.
- ATT-05: Capture location/photo close together; refresh evidence when it is stale. Use non-animated JPEG/PNG, at most 5 MiB and 20 megapixels under the current implementation. Convert mobile camera formats when necessary and constrain image dimensions/size before upload. Camera capture time is evidence time, not a chosen attendance time.
- ATT-06: Check-in uses `POST /attendance/check-in`. Check-out uses `POST /attendance/:id/check-out` with the exact owned open record ID. Disable repeated taps during submission. Show success only after a successful response; refresh own attendance afterward for status.
- ATT-07: One interval per employee per scheduled workday is supported. A closed current workday must not offer another check-in. An earlier open record blocks a new interval unless it has an owned pending forgotten-check-out request for that exact attendance ID. Every earlier open record must have such a request; rejected or withdrawn requests do not qualify. Refresh attendance and own requests after submission and allow current-workday check-in while HR review is pending. Use overall request status, not manager recommendation. Select only the current-workday record for check-out and location monitoring; earlier unresolved records remain in history with request status and resolution guidance. Unscheduled attendance may be recorded as `Not scheduled`; do not invent a mobile weekend prohibition.
- ATT-08: Server timestamps and saved schedule/timezone determine attendance status. Display history using each record's timezone. Preserve server `workDate`; never derive it from device date or replace record schedule snapshots with current settings.
- ATT-09: `/attendance/me` returns the latest 93 recorded intervals, not a complete 93-day calendar or paginated archive. Filter only that returned set and explain its limit. Do not fabricate absent days or claim older history is available.
- ATT-10: Open records may report `Missing check-out` after shift end. Offer a forgotten check-out request for an owned open record. Only HR approval changes recorded departure time; submitting the request leaves attendance open.
- ATT-11: Evidence metadata and photos are accessed through authenticated REST calls. Fetch private photo bytes with bearer authorization; resolve API-returned relative paths against the configured API origin without duplicating `/api`. Follow `private, no-store`; keep previews transient and never expose tokens in URLs. Show “No evidence available” for historical/manual records lacking evidence.
- ATT-12: A timeout/lost response has an unknown outcome. Fetch `/attendance/me` to reconcile before offering another attendance submission. Backend repeats preserve original timestamps/evidence, but evidence validation still runs; any retry needs valid recent evidence. Check-out retries retain the original record ID. Attendance is never queued for later offline upload.

### REQ — Employee requests

- REQ-01: Submit through `POST /requests`; list through `GET /requests/me`. Identity is session-derived. Support these exact backend type values:

| Type | Required fields in addition to `type` | Reason and optional fields |
| --- | --- | --- |
| `leave`, `holiday`, `sick`, `unpaid`, `urgent`, `mission` | `from`, `to` as date-only `YYYY-MM-DD` | `reason`: 5–500 trimmed characters; optional `attachments` |
| `excuse` | `from`, `to`, integer `durationMinutes`, `excuseType`, assigned `shiftId` UUID | Optional `reason`: 0–120 trimmed characters; optional `attachments` |
| `forgotten-check-out` | Owned open `attendanceId` UUID, `proposedCheckOut` ISO timestamp with offset | `reason`: 5–500 trimmed characters; attachments are unsupported |

- REQ-02: Date ranges are inclusive, ordered, at most 93 days, and cannot start before employment. Personal `holiday` is a time-off request, not a company holiday calendar. Use friendly type labels while preserving exact wire values.
- REQ-03: Excuse subtype is `leaving-early`, `arriving-late`, or `during-shift`. Use the schedule ID effective on every requested date; split a request that crosses schedule IDs. Duration is 1–1440 minutes and cannot exceed the effective shift length on any requested date. Each requested date charges that duration, rather than sharing one duration across the range.
- REQ-04: Explain the shared monthly Excuse limit: 240 minutes and at most 3 pending/approved requests per requested calendar month. Cross-month ranges split minutes by dates and count once in each month. Rejection/withdrawal releases reservations; a manager rejection alone does not. Any client allowance estimate is advisory and derived from current own requests; there is no dedicated balance endpoint.
- REQ-05: Backend overlap rules are authoritative. Pending/approved non-Excuse time off conflicts with overlapping date ranges; Excuse-to-Excuse overlap conflicts for the same shift and subtype. Forgotten check-out conflicts for the same attendance record. Surface 409 and refresh history.
- REQ-06: Forgotten departure must be in the past and at or after recorded check-in. Convert the chosen date/time from the record's timezone to an explicit ISO offset/UTC timestamp. Never silently interpret it in the device timezone.
- REQ-07: Optional request attachments use a JSON array of at most 3 objects `{ name, mimeType, content }`, where content is base64, maximum decoded size 512 KiB each, filename 1–200 trimmed characters, and MIME type PDF/PNG/JPEG. Follow the current DTO, not attendance multipart format. File selection is allowed here; request attachments are distinct from live attendance evidence. Keep submitted attachment content private and render only after safe decoding.
- REQ-08: History/details show all four statuses, submitted dates/reason, manager recommendation separately from final HR decision, reviewer names/times/reasons, returned `salaryDeductionDays`, and optional `lastChange`. Handle older records with absent manager fields. Show no calculated salary, payslip, or invented entitlement balance.
- REQ-09: Withdraw only an owned pending request with `PATCH /requests/:id/withdraw` and a 5–500 trimmed character reason. Withdrawn/rejected requests remain in history. There is no employee edit endpoint: correct a pending request by withdrawing and submitting a replacement. HR can reopen eligible approvals; reflect returned pending status and change history after refresh.
- REQ-10: Submission has no client idempotency-key contract. After an uncertain response, refresh history and reconcile the candidate before inviting manual resubmission; never automatically repeat request creation. Use similar refresh/reconciliation after uncertain withdrawal or manager review.

### MGR — Direct manager recommendations

- MGR-01: Load `GET /requests/managed`. Show only server-returned direct-report requests; the manager's own requests are excluded. Preserve already-reviewed items awaiting HR without offering a repeated recommendation.
- MGR-02: Submit `PATCH /requests/:id/manager-review` with `{ "status": "approved" | "rejected", "reason": "..." }`, reason 5–500 trimmed characters. Label the action as a recommendation to HR.
- MGR-03: Overall request remains `pending` after either recommendation. Manager review does not change attendance or apply deductions. Display `managerStage` independently: `not-required`, `pending`, `approved`, or `rejected`.
- MGR-04: Refresh after review, foreground return, or 403/409. Current assignments govern access; changing a manager/department or reopening can reset recommendations. Ordinary employee mobile screens never offer final HR decision or manager assignment controls.
- MGR-05: Tapping a `manager-review-required` notification opens the matching request in a bottom sheet after refreshing the authorized managed queue. Show the employee, request type, submitted details, reason, and current manager stage. When the server still reports `status: pending` and `managerStage: pending`, offer approval and rejection recommendations with a required reason. Disable duplicate submissions, keep entered text on a recoverable error, and refresh the queue and inbox after either result. If the request is gone, reassigned, or already reviewed, explain that it is no longer available for review and do not offer the actions.

### NTF — In-app notifications

- NTF-01: Load `GET /notifications` after sign-in, foreground return, and relevant successful mutations. Proposed active refresh interval is 30 seconds; pause polling in the background.
- NTF-02: Use server `items` and `unreadCount`; show title, message, time, read state, and unread filter. Employee events currently include `request-decided`, `request-reopened`, and `manager-reviewed`; assigned managers also receive `manager-review-required`.
- NTF-03: Mark accessible items read with `PATCH /notifications/:id/read`, no body needed. IDs are opaque strings, not necessarily UUIDs; URL-encode them. Repeated read preserves the original timestamp. Refresh gracefully on 404 when a live alert has disappeared.
- NTF-04: Resolve a `requestId` using current own requests or the authorized managed queue; there is no single-request GET endpoint. Follow request-list pagination until the matching ID is found or the list is exhausted. Resolve any accessible `attendanceId` through own attendance. Refresh before showing details and handle a no-longer-accessible target. A `manager-review-required` alert opens the matching request in the Department reviews bottom sheet; marking it read is separate from submitting a recommendation.
- NTF-05: Ordinary employee missing-check-out guidance comes from own attendance; the current notification service's missing-check-out alerts are HR/admin only. LOC-04 requires a departure warning/local notification; this does not introduce server push, email, or SMS.

## 6. REST integration checklist

All paths below are relative to a configured base URL ending in `/api`. Avoid adding `/api` twice.

Request list endpoints return paginated arrays (50 items by default, maximum 100). Follow `before` using the last returned request ID and retain the same `status` filter until a page has fewer than `limit` items. Refresh from the first page after mutations. History and notification target lookup must not assume the first page is complete; see hr-backend/API.md.

| Capability | Endpoints used by mobile |
| --- | --- |
| Session/account | `POST /auth/login`, `GET /auth/me`, `POST /auth/logout`, `POST /auth/password` |
| Attendance | `GET /attendance/me`, `GET /attendance/policy`, `POST /attendance/check-in`, `POST /attendance/:id/check-out` |
| Open-attendance monitoring | `POST /attendance/:id/location`; see MOBILE-LOCATION.md |
| Private evidence | `GET /attendance/:id/evidence`, `GET /attendance/:id/photos/:event` |
| Requests | `POST /requests`, `GET /requests/me`, `PATCH /requests/:id/withdraw` |
| Department recommendations | `GET /requests/managed`, `PATCH /requests/:id/manager-review` |
| Notifications | `GET /notifications`, `PATCH /notifications/:id/read` |
| Schedule lookup when needed | `GET /schedules` (read-only; own attendance already returns assigned schedule) |
| Connection diagnostics | `GET /health` (public; not a substitute for session validation) |
| Real estate sales | `GET /sales/access`, own/team activity and performance reads, activity creation/correction and authorized review; see MOBILE-SALES.md |

Mobile must not use `/employees`, global `/attendance` reports/exports/corrections, global `/requests`, `/requests/:id/decision`, `/requests/:id/reopen`, department administration, `/payroll*`, `/audit`, or settings/schedule mutation endpoints for these employee features.

Configure separate development and production API addresses. The existing host development address is `http://127.0.0.1:3002/api`; on a physical phone, loopback refers to the phone, so use a reachable development host address. Configure emulator networking explicitly. Use HTTPS for production and never disable certificate validation. Native bearer calls go directly to NestJS; the Next.js dashboard proxy is not the mobile API base.

JSON endpoints use `application/json`; manual attendance capture uses multipart, monitoring updates use JSON, and evidence photos return JPEG bytes. DTOs reject extra fields: send only the fields allowed for the chosen operation/type. Parse nullable and optional fields faithfully. Do not assume a status field exists on mutation responses when it is only added by the attendance read endpoint.

## 7. Errors and connection behavior

| Outcome | Required employee experience |
| --- | --- |
| 400 | Explain invalid input/evidence or absent employee association; preserve editable form state |
| 401 | For login, show invalid credentials; for protected actions, clear session and request sign-in |
| 403 | Explain denied operation or outside-office evidence; preserve session unless a later authentication check fails |
| 404 | Explain unavailable/not-owned record; refresh authorized lists |
| 409 | Show state/overlap/allowance conflict and refresh affected records; never bypass the rule |
| 413 | Explain oversized photo and recapture/reduce size |
| 429 | Explain login lockout and waiting period |
| Network failure/timeout | Distinguish failure to connect from rejected input; mutation outcome may be unknown, so reconcile |
| 5xx | Show service-unavailable guidance and offer a deliberate retry after reconciliation |

Normalize NestJS `message` strings or arrays into readable errors. Avoid showing stack traces or sensitive raw payloads. Every data screen needs loading, empty, error/retry, and refreshed states. Keep unsent form input in memory during recoverable failures, but clear personal data on logout/account changes. Do not present stale attendance as current or confirm an offline write. HR manual handling is the operational fallback during an outage; its process needs company confirmation.

## 8. Quality and privacy requirements

- Store session tokens using platform secure storage; redact tokens, passwords, national IDs, coordinates, attachment content, and photos from logs/crash reports.
- Collect location for attendance events and approved monitoring of open attendance only; never track off duty. Request camera/location access in context, explain background monitoring, and stop monitoring after checkout/logout/account changes. Stop camera resources when leaving capture flows. Delete temporary captures on completion/cancellation, and clear remaining files on the next startup if an interrupted flow left them behind.
- Keep employee details, request attachments, and evidence behind authenticated screens; clear account-specific state when switching users.
- Use readable labels, accessible tap targets, screen-reader names, visible progress, and explicit submission results. Do not encode request status only by color.
- Time presentation must respect company/record IANA timezones and daylight-saving rules, including overnight shifts; date-only request values must remain date-only.
- Proposed usability target: check-in/check-out requires one clear capture-and-submit flow without repeated data entry. Final timing, supported platforms, languages, and accessibility targets remain open decisions.
- Do not claim a 3-second attendance guarantee. The existing backend benchmark exceeded the provisional target under a 100-request burst; agree and test realistic pilot load/network conditions.

## 9. Acceptance scenarios

Use isolated test accounts and databases. Never test mutations against real employee/company records.

| ID | Scenario and required result |
| --- | --- |
| AC-01 | Active employee signs in; restart validates the stored token; profile and company settings match the REST response |
| AC-02 | Expired/revoked/deactivated account receives 401 and loses local access; a connection outage instead displays a recoverable network error |
| AC-03 | Password change succeeds and forces sign-in again; logout clears local personal state and revokes the server session when connected |
| AC-04 | Valid fresh office GPS/photo check-in appears once in mobile and HR dashboard with the same record ID/server timestamp |
| AC-05 | Valid check-out closes the exact owned record and appears in both clients; repeated taps/retries do not replace its original event |
| AC-06 | Outside radius, denied permissions, poor accuracy, stale capture, invalid/oversized photo prevent successful attendance and leave backend state unchanged |
| AC-07 | Lost attendance response is reconciled; evidence is refreshed before retry; an old check-out retry cannot close a later record |
| AC-08 | Earlier open workday prevents a new check-in until an owned pending forgotten-check-out request exists for each earlier open record; submission enables current-workday check-in without closing the earlier record. Rejected/withdrawn requests block future new intervals until resolved; the current interval remains usable. Closed current workday does not offer a second interval. Check-out and location monitoring target only the current-workday record |
| AC-09 | Overnight shift and device timezone differing from company show backend workDate and correct saved-record local times |
| AC-10 | History reflects only returned intervals, including records without evidence; other employees' evidence is inaccessible |
| AC-11 | Every supported request type submits its exact allowed body; date/reason/shift/attachment constraints and 409 conflicts are shown correctly |
| AC-12 | Excuse accepts exactly 240 minutes/3 requests, rejects excess, splits cross-month reservations, and releases them on withdrawal/final rejection |
| AC-13 | Forgotten check-out submission leaves attendance open; HR approval closes it with audited correction and no fabricated evidence |
| AC-14 | Pending own request can be withdrawn; approved/rejected/withdrawn requests cannot; HR reopening is reflected in history after refresh |
| AC-15 | Assigned manager receives a `manager-review-required` alert; tapping it opens the matching request bottom sheet with approval/rejection recommendations and a required reason. Only authorized pending queue items can be reviewed; self-review is denied, and the recommendation remains pending for HR with no deduction/attendance effect |
| AC-16 | Ordinary employee has no privileged controls; assignment change invalidates manager action gracefully; server 403 remains enforced |
| AC-17 | Notification count/read state matches API and persists across sign-in; opaque IDs work; paginated request lookup finds older targets; removed alerts, reassignment, and stale links recover safely |
| AC-18 | A timed-out request creation is reconciled without automatic duplicate POST; offline attendance is never queued or shown as submitted |
| AC-19 | Switching accounts leaves no previous employee data/evidence; stored secrets and sensitive captures do not appear in logs |
| AC-20 | Pilot on agreed real devices verifies camera formats, location accuracy, permission recovery, lifecycle refresh, and HR/mobile record agreement |
| LOC-AC-01 | Tracking starts/resumes for the owned open record, reports while foreground/background on supported real devices, and stops after checkout/logout/account change/401 |
| LOC-AC-02 | One outside reading cannot start a timer; confirmed departure starts five minutes. Reliable return cancels it. The mobile countdown matches server `returnBy` |
| LOC-AC-03 | Fresh outside reports through expiry produce exactly one audited checkout at the server deadline, visible in mobile and HR, with no fabricated photo or payroll deduction |
| LOC-AC-04 | Denied/disabled location, poor accuracy, boundary uncertainty, network/reporting loss and stale fixes leave attendance open, show unavailable location, cancel the timer and create no deduction |
| LOC-AC-05 | Restart preserves a valid server deadline; recovery after stale coverage starts a new confirmation/full return window. Wrong ownership, invalid or replayed timestamps, and closed-record updates are rejected/reconciled |

Verify model serialization and timezone conversions with focused automated tests; verify workflows through REST integration and Flutter widget/device tests appropriate to each feature. Acceptance requires passing Flutter analysis/tests, the agreed device pilot, and recorded evidence of the scenarios above. Mock-only success is insufficient for backend integration acceptance.

## 10. Open decisions and dependencies

| Decision | Current baseline / action |
| --- | --- |
| Android/iOS and minimum OS versions | Flutter confirmed; confirm target platforms/devices before platform-specific delivery |
| Interface languages | Confirm English, Arabic, or both; Arabic requires RTL verification |
| Production API/hosting | Obtain reachable HTTPS URL and verify server connectivity; no production deployment is implied by this BRD |
| Company timezone | Currently Africa/Cairo; always consume API value, with HR confirmation before launch |
| Request deduction policy | HR must confirm current all-non-forgotten-check-out 1-day/3-day behavior, especially sick/mission/Excuse |
| Evidence and attachment retention | Company must define duration/access/deletion policy; mobile must minimize temporary copies |
| Attendance evidence limits | Current server limits are the implementation baseline; confirm technical policy and test device capture quality |
| Outage/account support | Confirm HR contact, account credential distribution/reset process, and manual attendance fallback |
| Distribution and ownership | Confirm store/private distribution, release signing, update process, and mobile support owner |
| Performance/pilot | Fewer than 100 employees is the current scale; agree peak traffic, acceptable response times, devices, and pilot approver |

Proceed with API-backed scope and configurable environment setup while decisions are pending. Record assumptions explicitly; do not describe pending choices as approved. Release depends on relevant decisions and pilot acceptance.

## 11. Requirement traceability

| Requirements | Backend references to inspect |
| --- | --- |
| AUTH | `hr-backend/src/auth/auth.controller.ts`, `auth.service.ts`, `dto/auth.dto.ts`; `src/employees/types/employee.type.ts` |
| ATT | `hr-backend/src/attendance/attendance.controller.ts`, `attendance.service.ts`, `attendance-evidence.service.ts`, `attendance-time.ts` |
| LOC | `hr-backend/src/attendance/attendance-location.service.ts`, `attendance.controller.ts`, `hr-backend/test/hr.e2e-spec.ts`; MOBILE-LOCATION.md |
| REQ / MGR | `hr-backend/src/requests/requests.controller.ts`, `dto/request.dto.ts`, `types/employee-request.type.ts`, `requests.service.ts` |
| NTF | `hr-backend/src/notifications/notifications.controller.ts`, `notifications.service.ts` |
| REST integration | `hr-backend/API.md`, `hr-backend/test/hr.e2e-spec.ts`, relevant feature tests |

These paths are references for contract verification, not dependencies to import into mobile code.

## 12. Delivery order and completion

1. Create the Flutter project and environment configuration; implement secure authentication, API client, profile loading, error handling, and timezone support. Complete AC-01–03.
2. Implement Home, policy loading, live GPS/camera capture, check-in/check-out, reconciliation, history, and evidence. Add open-attendance background monitoring, unavailable-location recovery, and return warnings using LOC-01–06. Complete AC-04–10, LOC-AC-01–05, and attendance portions of AC-18–20.
3. Implement all employee request forms, attachments, history/details, forgotten check-out, and withdrawal. Complete AC-11–14 and request portion of AC-18.
4. Implement manager recommendations and notification inbox/routing/foreground refresh. Complete AC-15–17.
5. Implement the additive real estate Sales screens and team verification in MOBILE-SALES.md. Complete SALES-AC-01–08 against the REST backend and dashboard.
6. Verify privacy, device compatibility, permissions, lifecycle behavior, and full REST-to-dashboard workflows. Complete AC-19–20, resolve release decisions, and record pilot approval.

Mobile delivery is complete when all in-scope requirements and acceptance scenarios pass, the app works with the existing REST backend without privileged bypasses, setup/verification documentation is available, and the business/technical owners accept the agreed device pilot. Backend functionality alone is not mobile completion.
