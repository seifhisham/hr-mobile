# Multi-tenancy implementation and verification

Updated 2026-10-17. Existing uncommitted work was preserved. All application backend
communication remains REST; no database client, company switcher, owner administration,
branch picker, offline attendance queue, or new package was introduced.

## Changed files

- `lib/src/ui/auth/login_screen.dart`, `providers/auth_provider.dart`,
  `lib/src/data/repositories/auth_repository*.dart`, `lib/src/services/auth_service.dart`:
  explicit validated company code through every login caller; normalized workspace/email,
  unmodified password; opaque token remains in platform secure storage. Login attempts
  clear the previous local session, including when the next credentials are rejected.
  Storage operations are ordered and login/profile completions cannot revive a logged-out
  session. A 401 or rejected `/auth/me` ends access; other protected 403 responses validate
  `/auth/me` alone. Network failure does not establish invalid authentication.
- `lib/src/data/models/user_model.dart`, `lib/src/ui/account/account_screen.dart`:
  company ID, workspace and company status metadata; company code displayed on account.
- Attendance, requests, sales and notifications provider/refresh/form/preview files under
  `lib/src/ui/`: personal state, pending actions, polling and previews use company +
  workspace + user + employee identity. Shared authorization rejects old-session success
  responses, including private photo bytes. Existing provider disposal and generation
  guards stop old controllers and location reports.
- `lib/src/data/models/attendance_model.dart`,
  `lib/src/ui/attendance/attendance_screen.dart`, `attendance_summary.dart`:
  parse/compare/display returned branch IDs/names; historical records retain their own
  name, workDate, timezone and shift. Capture continues to reload server policy before
  GPS/photo acquisition; no branchId is submitted. Existing current-workday open-record
  monitoring, serialized fresh fixes, unavailable-location behavior and server deadlines
  remain in place. Older unresolved records retain the existing forgotten-checkout flow.
- `lib/src/services/attendance_service.dart`: private evidence paths reject query strings
  and fragments as well as external URLs; bearer downloads remain transient bytes with
  redirects disabled. Request attachments continue through authenticated inline JSON;
  explicit PDF export remains an employee action.
- `lib/src/config/app_config.dart`, `.env.example`, `SETUP.md`, `MOBILE-API.md`,
  `LOCATION-DEVICE-CHECKS.md`: release HTTPS requirement, reachable development-address
  example, no default workspace, corrected login example and current monitoring scope.
- English/Arabic translation JSON and generated localization keys: company-code labels
  and validation. Authentication/backend test callers and fixture login bodies now supply
  workspace explicitly. `test/multitenancy_test.dart` adds focused company-isolation,
  invalid-session, delayed-media, login/logout race and branch-policy checks.

## Checks

- `flutter pub get`: passed; no dependency added.
- Localization generation: passed.
- Full `flutter test --reporter expanded`: 204 passed, 6 opt-in cases skipped.
- Latest focused `test/multitenancy_test.dart`: 8 passed, including two regression cases
  added after the full run (logout during login; schedule 403 without recursive validation).
- `flutter analyze`: passed, no issues.
- Final auth/config/multi-tenancy selection: 23 passed.
- `git diff --check`: passed.
- Android `flutter build apk --debug --no-pub`: blocked before compilation by Gradle
  `java.io.IOException: Unable to establish loopback connection`.
- `flutter devices`: Windows, Chrome and Edge only; no physical device connected.

## Backend and release dependencies

The adjacent `C:/work/hr-system/hr-backend` source was inspected read-only to verify
current login validation, `/auth/me` metadata, assigned-branch policy, record mapping,
and company suspension/revocation behavior. No real employee records were changed.
Its current integration fixture requires a disposable PostgreSQL development cluster
via `HR_PG_TEST_ADMIN_URL`; none is configured in this session. No live backend acceptance
is claimed. The older SQLite/in-memory mobile fixture scripts do not verify the completed
multi-company PostgreSQL implementation.

Run live REST acceptance with disposable accounts in two companies sharing an email:
company-specific login/profile/history/media, switching while calls are pending,
revocation/suspension, permission-denied retention, assigned branches and transfers,
protected photos, request attachments, notifications, manager recommendations and sales.
Pass the explicit fixture code using `--dart-define=TEST_WORKSPACE=<code>` where applicable.
Configure a reachable development backend or production HTTPS API URL before device use.

## Physical-device checks remaining

Follow `LOCATION-DEVICE-CHECKS.md`: Android/iOS camera and GPS, precise/Always permission
recovery, background/locked stationary reporting, foreground reconciliation, departure
confirmation and returned deadlines, stale/missing/uncertain location with no client
checkout/deduction, account-change shutdown, notifications and OS battery/termination
limits. Verify Arabic/RTL, dark mode and larger text on actual phones.

Native Android/iOS location/foreground-service/notification permissions and iOS background
mode already exist and were inspected; native folders were not modified, per workspace
instructions. iOS compilation/signing needs a Mac. Background delivery remains best effort;
a terminated app is not automatically restarted, and no stale coordinates are queued.
