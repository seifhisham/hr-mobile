# hrmobile

Generated with the Flutter Scaffolding Wizard.

## What's inside
- Opinionated theme with Material 3
- Onboarding presentation starter
- Routing scaffold using `go_router`
- State: riverpod
- Backend: custom

## Employee authentication

Set `API_BASE_URL` in `.env` to a reachable backend origin or address ending in `/api`; the client adds the prefix once. Stop and rerun after changing it. See [SETUP.md](SETUP.md) and [MOBILE-API.md](MOBILE-API.md).

Login stores the opaque bearer token in platform secure storage. Startup validates it through `/auth/me` and loads the assigned schedule. Connection failures offer retry without deleting the token; protected 401 responses clear the session. Account displays read-only employee/company details and supports password change and sign-out. Profile data refreshes when Account opens and when the app resumes; an unsuccessful refresh identifies previously loaded details. Accounts and password resets are provided by HR.

Run `flutter pub get`, `flutter analyze`, and `flutter test`. The optional REST check in `test/auth_backend_test.dart` requires an isolated local backend with a throwaway employee `mobile-employee@example.test`, national ID `00123456789012`, initial password `Isolated-employee-password-2026`, and the default company/schedule. Run it with `flutter test test/auth_backend_test.dart --dart-define=AUTH_TEST_API=http://127.0.0.1:PORT/api`. It changes that test account's password and revokes sessions; use a fresh in-memory test database for each run, never real company records.

## Attendance

Home shows the server workday, assigned schedule, current attendance and timestamps in the saved record timezone, separately from the company calendar date. Home and Attendance share fresh capture/check-in/check-out controls, older-open record guidance and forgotten check-out links, with entry/foreground refresh and retry/settings recovery. Open Attendance for history and evidence. The app loads current policy and the server workday, shows recent intervals using their saved timezone/schedule, and captures a new camera photo and GPS fix for each check-in/check-out. A closed workday cannot start again; an older open record shows HR correction guidance. After live camera capture, the shared check-in/check-out path prepares the photo in a background isolate: bake orientation, proportionally resize to a maximum edge of 1280 without enlargement, remove metadata, and encode JPEG at quality 85. Both actions open an in-app camera modal with a live preview and Capture/Cancel controls. The camera is released on dismissal, backgrounding or sign-out; late captures are deleted. Audio recording is disabled. Compressed bytes stay in memory. The original capture timestamp and GPS evidence are retained, and stale evidence is rejected before POST. Preparation failures are recoverable and never upload evidence. Returned temporary camera files are removed in `finally`, including failed or abandoned flows; interrupted captures are discarded rather than uploaded.

Lost/invalid responses trigger a server refresh before retry. If reconciliation fails, submission stays blocked until the outcome can be checked. Evidence is never queued for offline upload. Attendance and sales responses/errors are excluded from debug Dio logs; request bodies, headers and successful bodies are omitted to protect credentials and employee data.

Run `node test/support/run_attendance_backend.mjs C:/path/to/hr-backend` against a built backend checkout. The harness starts a fresh in-memory database on a random loopback port, provisions a throwaway employee through REST, runs `test/attendance_backend_test.dart`, and closes the server. It checks compressed landscape/portrait multipart uploads, saved timestamps/GPS, private JPEG retrieval, evidence rejection and original-event preservation. It never connects to the configured company API.

Photo checks: `flutter test test/attendance_photo_test.dart test/attendance_test.dart`. Host measurements: `flutter test test/attendance_photo_benchmark_test.dart --dart-define=PHOTO_BENCHMARK=true`; results are saved to `artifacts/attendance_compression/benchmark.json`. These deterministic synthetic fixtures compare the old 1600-pixel helper and new 1280-pixel helper on identical inputs. They exclude native camera/picker processing, GPS, file reads, network, and real-phone performance.

Phone verification still required: precise-location denial/settings recovery, disabled GPS, camera denial/cancellation, weak GPS, outside-office rejection, camera return/restart, overnight workday, successful check-in/out and lost-response recovery. Android native permissions and iOS usage descriptions are included. Follow the background-location guidance in SETUP.md on the Mac build host. Attendance history supports inclusive workday/date and status filters over the returned records. View evidence loads authenticated metadata and private photos into transient memory, with retry and no-evidence states. Open attendance records link directly to a forgotten-check-out request. Submitting it leaves attendance open until HR approval.

Attendance location monitoring follows the exact open record from `/attendance/me` and `policy.tracking`. Android/iOS report fresh fixes at the policy interval, including a timed capture when stationary; reports are serialized and never queued. The app-wide warning shows the server return deadline, offers explained permission recovery, and posts a local return notification. The backend alone confirms departure and automatic checkout. Missing location leaves attendance open; connection loss is shown separately. Logout/account change/401 stop monitoring and clear warnings. Native configuration and real-device acceptance are documented in [LOCATION-DEVICE-CHECKS.md](LOCATION-DEVICE-CHECKS.md). Phone operation and terminated-app delivery are not verified by host tests.

## Employee requests

Open Requests from Home to filter your own history by status/type, submit any of the eight supported request types, view manager recommendations separately from final HR decisions, and withdraw pending requests with a reason. Forms validate inclusive date ranges, employment dates, reasons and assigned-shift Excuse minutes. The server enforces overlaps and monthly allowances. Current returned deduction policy is explained before submission; HR policy confirmation remains a release decision.

Attachments use the system picker (`file_picker`): up to three PDF/PNG/JPEG files of 5 MB each. Selected bytes are validated and sent as inline base64 JSON. Mobile picker cache is cleared after selection. Image previews stay in memory and close on sign-out; PDFs are saved only through an explicit system save action. User-exported PDFs remain where the user chose to save them. Native picker/save behavior and interrupted-file cleanup still need device verification.

Forgotten check-out selects an owned open record and interprets the chosen departure in its saved IANA timezone. Nonexistent clock-change times are rejected; repeated times require an explicit UTC occurrence. No mobile attendance correction or fabricated evidence is created.

Lost mutation responses refresh own history before any deliberate retry. A failed reconciliation blocks submission; request creation is never automatically repeated. Requests/history refresh on entry and foreground return. Department reviews is available from manager notifications or Requests when the authorized queue contains items. Eligible items offer approval/rejection recommendations to HR with a 5–500-character trimmed reason. Reviews keep the overall request pending, refresh the managed queue and notifications, and reconcile lost responses without automatically repeating the review.

`flutter test` covers payloads, validation, clock changes, attachment decoding, reconciliation and English/Arabic screens, including small phones, large text and landscape. The opt-in REST test requires a fresh local in-memory backend/database; never use company records. With a built backend and Node installed, run from this project:

```powershell
node test/support/run_requests_backend.mjs C:/path/to/hr-backend
```

The harness starts an isolated loopback server on a random port, provisions throwaway accounts through REST, runs `test/requests_backend_test.dart`, and shuts the server down. It verifies all types, attachments, overlap, the 240-minute/3-request limit, cross-month reservations, withdrawal, HR decisions/reopening, forgotten departure correction, and manager recommendations with self-review, repeated-review and changed-assignment rejection. HR endpoints are used only by this test harness; employee runtime code uses own-request REST endpoints exclusively.

## Notifications

The bell on Home and screen headers opens the notification inbox. Its badge uses the API unread count; the inbox shows server titles/messages, company-local times, read state and an unread-only filter. Read state is saved by the backend, including across sign-out/sign-in. A removed alert refreshes the inbox instead of opening stale content.

Notifications load after sign-in, on foreground return, after successful request mutations and every 30 seconds while the signed-in app is active. Background polling stops. A failed refresh offers retry and identifies cached inbox content; the badge hides an unverified count. This is an in-app inbox, without background push.

Request links refresh own requests before navigation. Manager-review alerts refresh all cursor pages of the authorized department queue and open the matching request in a bottom sheet. Details show recommendation actions only for a currently assigned pending manager stage; 403/404/409 disables further review and refreshes the queue and inbox. Missing or inaccessible targets remain recoverable. Eligible department requests offer manager recommendations; already-reviewed requests remain visible while awaiting HR.

Focused manager notification REST acceptance (fresh in-memory database and throwaway accounts):

```powershell
node test/support/run_requests_backend.mjs C:/path/to/hr-backend test/manager_notifications_backend_test.dart
```

This checks both recommendations, read marking, queue/inbox refresh and the overall pending status. Its fixtures use the current employee `managerId` assignment contract. The older broad request harness still uses the removed department-manager assignment endpoint and needs a separate fixture update.

Default tests cover opaque notification IDs, read timestamps, removed alerts, late/disposed responses, mutation refresh, foreground/background polling, sign-out cleanup and English/Arabic layouts. The isolated request REST harness also verifies notification events, read-state persistence across sign-in and reopened-request alerts.

## Getting started

If you downloaded this project from the web wizard, create platform folders first (skip if you used the FlutterInit CLI):
```bash
flutter create . --project-name hrmobile --org com.wsc
```

Then:
```bash
flutter pub get
dart format .
flutter run
```

## Sales

Open **Sales** from the employee navigation or Home shortcut. The monthly overview shows server-returned verified results, separate currency totals and HR targets. Register a completed meeting, viewing or signed sale/lease; submitted work stays pending until verified. Returned entries show the review reason and can be corrected/resubmitted. Verified entries need a reviewer return before correction.

Submission access comes from `/sales/access`, not department names. Disabled employees retain historical reads. Authorized managers can open **Team sales reviews** without personal submission access; verification is final for sales performance. Self-review controls are hidden, and the API enforces authorization. Targets and exports remain in the dashboard.

English/Arabic screens use the existing app theme and components. Access, summaries and details refresh on foreground return and after writes. Uncertain submissions retain their UUID and exact payload in signed-in memory; check the saved result before retrying. Only a confirmed missing creation allows retry of the original submission or deliberate editing of its unsaved details. Sales writes are not queued offline; signing out clears unresolved submissions and sales data. Sales payloads and error bodies are excluded from network logs.

The feature uses the existing `API_BASE_URL` configuration and bearer client; no extra permissions or dependencies are needed. Contracts and acceptance cases: [MOBILE-API.md section 12](MOBILE-API.md#12-real-estate-sales-complete-mobile-rest-contract) and [MOBILE-REQUESTS.md section 10](MOBILE-REQUESTS.md#10-implementation-request-real-estate-sales-in-the-existing-mobile-app).

Run model/retry/widget checks with `flutter test`. Run real REST checks against a built backend checkout with Node installed:

```bash
node test/support/run_sales_backend.mjs C:/path/to/hr-backend
```

The harness creates a fresh in-memory database and throwaway accounts on a random loopback port, runs the mobile sales service/controller against it, then closes the server. It verifies all activity types, replay, verification/return/correction, targets and currency separation, strict validation, duplicate references, stale revisions, self/outside-team denial, access removal and lost-response reconciliation. Dashboard endpoints are used only to provision isolated test fixtures and targets. Do not run this acceptance test against company data.

Sales changes live in `lib/src/data/models/sales_activity.dart`, `lib/src/data/repositories/sales_repository.dart`, `lib/src/services/sales_service.dart` and `lib/src/ui/sales/`; employee model, routes, navigation, Home, app lifecycle wrapper, logging and translations connect the feature to the existing app. No native platform configuration or `.env` values were changed. A connected phone and interactive dashboard pilot still need acceptance evidence; isolated REST and widget checks do not replace that pilot.
