# Android push notification testing

Android initializes Firebase from `lib/firebase_options.dart`, creates the
`hodour_push` notification channel, and requests notification permission.
iOS Firebase initialization and APNs integration are deferred.

## Test with the backend

1. Connect an Android phone with Google Play services, or start a Google Play
   emulator. Run `flutter run` and allow notifications when prompted.
2. Sign in to the intended test company/account. The app POSTs its persistent
   installation UUID and FCM registration token to `/api/push/devices` using the
   current session. Tokens are stored securely and never printed.
3. Have an authorized backend operator confirm the binding exists for this
   company/account/session, without exposing its token.
4. Use a synthetic authorized HR event for a consenting test account/device,
   following the backend's `PUSH.md`. Confirm the corresponding inbox item exists.
5. Check background delivery first, then repeat with the app in the foreground.
   Foreground messages use a local notification; background messages with a
   notification payload are displayed by Android, without a second local copy.
6. Tap the notification. A signed-in user is taken to the existing notification
   inbox. A signed-out user must sign in first. Also test by dismissing the app
   from Recents and tapping a newly delivered notification.

Console test messages do not create records in the REST inbox, so the inbox may
be empty. Notification payloads do not select arbitrary routes or grant access
to records. The inbox continues to load authorized data from the backend.

The installed Firebase Messaging SDK deprecates registration tokens in favor of
installation IDs. The backend explicitly requires registration tokens; the app
keeps that flow without mixing registration schemes.

## Delivery prerequisites

- Use a full rebuild after native/Firebase setup changes, rather than hot reload.
- The notification channel and app notification permission must be enabled in
  Android settings. Denied permission does not block the rest of the app.
- Open the app at least once after installation. If force-stopped from Android
  settings, reopen it before testing delivery again.
- The mandatory-update gate is disabled by default during testing; see
  `APP-UPDATES.md` before enabling it for production.
- Data-only messages refresh the inbox when received in the foreground; they
  intentionally do not display an alert or perform background business work.

## Registration lifecycle

Registration runs after login/session restoration and token rotation. The UUID
persists in SharedPreferences across logins, and the token stays in secure
storage. No user/company IDs are submitted. Requests use the shared API client
and expected-session-revision guard. Transfers are serialized, stale queued
work is discarded, and late results cannot update the new session's state.

Temporary failures get at most three automatic attempts with exponential backoff
and jitter. HTTP 429 Retry-After seconds are honored, including on resume/token
rotation. Pending registration retries on resume; HTTP 400/401/403 stop retries
for that session. Successful registration does not repeat on every profile poll.

Logout attempts `DELETE /api/push/devices/:deviceId` with the old session before
clearing credentials, with a five-second total wait budget. It then performs the
existing server logout. Offline failure cannot prevent local sign-out. If both
remote operations fail, the server cannot learn of local logout until session
revocation/expiry. A notification already submitted to FCM cannot be recalled.

## Build and install

Set `API_BASE_URL=https://hr.wallstreetwsc.com/api` in the locally managed `.env`
before building (do not put server Firebase credentials in mobile assets).
Run `flutter pub get`, then `flutter build apk --debug`. Install on a connected
device with `flutter install --debug`, or run `flutter run` directly. For release
use the project's existing signing setup and `flutter build apk --release` or
`flutter build appbundle --release`. A full rebuild is required; hot reload is
insufficient. Keep the same application/signing identity when updating an
installation, or Android may require uninstalling (which erases local data).

The backend sender must be deployed/enabled separately with its Firebase Admin
credentials. HTTP registration can succeed even when the sender is disabled.
End-to-end verification requires both a registered device and actual authorized
backend-to-phone delivery. Firebase Console tests alone do not verify this flow.

References: [FCM setup](https://firebase.google.com/docs/cloud-messaging/flutter/get-started)
and [message handling](https://firebase.google.com/docs/cloud-messaging/flutter/receive-messages).
