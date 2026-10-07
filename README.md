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

Open Attendance from Home. The app loads current policy and the server workday, shows recent intervals using their saved timezone/schedule, and captures a new camera photo and GPS fix for each check-in/check-out. A closed workday cannot start again; an older open record shows HR correction guidance. Photo preparation strips metadata and produces a JPEG up to 1600 pixels per side. Temporary camera files are removed after capture; interrupted captures are discarded rather than uploaded.

Lost/invalid responses trigger a server refresh before retry. If reconciliation fails, submission stays blocked until the outcome can be checked. Evidence is never queued for offline upload. Backend error bodies appear in debug Dio logs; request bodies, headers and successful bodies are omitted to protect credentials and employee data.

The optional `test/attendance_backend_test.dart` uses the same throwaway employee fixture described above, with **no existing attendance**. Run `flutter test test/attendance_backend_test.dart --dart-define=ATTENDANCE_TEST_API=http://127.0.0.1:PORT/api` against a fresh database. It creates attendance/evidence records; never run it against company data.

Phone verification still required: precise-location denial/settings recovery, disabled GPS, camera denial/cancellation, weak GPS, outside-office rejection, camera return/restart, overnight workday, successful check-in/out and lost-response recovery. Android native permissions and iOS usage descriptions are included. For iOS foreground-only geolocation, follow the geolocator compiler-flag guidance in SETUP.md on the Mac build host. Attendance history supports inclusive workday/date and status filters over the returned records. View evidence loads authenticated metadata and private photos into transient memory, with retry and no-evidence states. Open attendance records link directly to a forgotten-check-out request. Submitting it leaves attendance open until HR approval.

## Employee requests

Open Requests from Home to filter your own history by status/type, submit any of the eight supported request types, view manager recommendations separately from final HR decisions, and withdraw pending requests with a reason. Forms validate inclusive date ranges, employment dates, reasons and assigned-shift Excuse minutes. The server enforces overlaps and monthly allowances. Current returned deduction policy is explained before submission; HR policy confirmation remains a release decision.

Attachments use the system picker (`file_picker`): up to three PDF/PNG/JPEG files of 512 KiB each. Selected bytes are validated and sent as inline base64 JSON. Mobile picker cache is cleared after selection. Image previews stay in memory and close on sign-out; PDFs are saved only through an explicit system save action. User-exported PDFs remain where the user chose to save them. Native picker/save behavior and interrupted-file cleanup still need device verification.

Forgotten check-out selects an owned open record and interprets the chosen departure in its saved IANA timezone. Nonexistent clock-change times are rejected; repeated times require an explicit UTC occurrence. No mobile attendance correction or fabricated evidence is created.

Lost mutation responses refresh own history before any deliberate retry. A failed reconciliation blocks submission; request creation is never automatically repeated. Requests/history refresh on entry and foreground return. Manager recommendation actions are the next delivery step; the authorized department queue is available from manager notifications or Requests when it contains items.

`flutter test` covers payloads, validation, clock changes, attachment decoding, reconciliation and English/Arabic screens, including small phones, large text and landscape. The opt-in REST test requires a fresh local in-memory backend/database; never use company records. With a built backend and Node installed, run from this project:

```powershell
node test/support/run_requests_backend.mjs C:/path/to/hr-backend
```

The harness starts an isolated loopback server on a random port, provisions throwaway accounts through REST, runs `test/requests_backend_test.dart`, and shuts the server down. It verifies all types, attachments, overlap, the 240-minute/3-request limit, cross-month reservations, withdrawal, HR decisions/reopening and forgotten departure correction. HR endpoints are used only by this test harness; employee runtime code uses own-request REST endpoints exclusively.

## Notifications

The bell on Home and screen headers opens the notification inbox. Its badge uses the API unread count; the inbox shows server titles/messages, company-local times, read state and an unread-only filter. Read state is saved by the backend, including across sign-out/sign-in. A removed alert refreshes the inbox instead of opening stale content.

Notifications load after sign-in, on foreground return, after successful request mutations and every 30 seconds while the signed-in app is active. Background polling stops. A failed refresh offers retry and identifies cached inbox content; the badge hides an unverified count. This is an in-app inbox, without background push.

Request links refresh own requests before navigation. Manager-review alerts resolve against the authorized department queue; details there never offer employee withdrawal or final HR decisions. Missing or inaccessible targets remain recoverable. Department recommendation actions remain pending.

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
