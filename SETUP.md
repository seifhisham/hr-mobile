# 🎉 Welcome to Hodour!

This project was generated dynamically based on your specific requirements. Before running your app for the first time, follow this brief setup guide to configure the required environment variables, permissions, and dependencies locally.

---

## 1. 📱 Platform folders (web download only)

The web wizard ZIP does **not** include native runners (`android/`, `ios/`, `web/`, `windows/`, `macos/`, `linux/`). Those are created only via the Flutter CLI.

Skip this step if you generated the project with the FlutterInit CLI (`flutter create` already ran).

From the project root:
```bash
flutter create . --project-name hodour --org com.wsc
```

This adds the platform folders without overwriting your generated Dart sources.

---

## 2. 📦 Initial Dependencies & Generation

First, fetch all pub packages, then format the generated Dart (templates are not pre-formatted):
```bash
flutter pub get
dart format .
```

### Code Generation
*(No initial code generation required for your main stack)*

### Localization
Since you chose to include `easy_localization`, run these commands whenever you add or modify string translations to generate your keys correctly:
```bash
flutter pub run easy_localization:generate -S assets/translations -O lib/src/core/i18n -o locale_keys.g.dart
```

---

## 3. 🎨 Native Splash Screen Setup

This project uses `flutter_native_splash`.

**To apply your custom app launch screen:**
1. Place your transparent splash logo at [`assets/images/splash.png`](assets/images/splash.png).
2. Open [`flutter_native_splash.yaml`](flutter_native_splash.yaml) in the root of your project.
3. Uncomment the `image:` paths so it looks like:
   ```yaml
   flutter_native_splash:
     color: "##183C35"
     image: assets/images/splash.png
     android_12:
       image: assets/images/splash.png
       icon_background_color: "##183C35"
   ```
4. Apply the native configuration natively by running:
```bash
dart run flutter_native_splash:create --path=flutter_native_splash.yaml
```
*Note: Run this command every time you change your splash image or background color.*

---

## 4. 🔐 App Permissions (Android & iOS)

Based on your chosen flags (e.g.  , Geolocator ), you must configure Native permissions before testing these features.

### Android Setup
Open [`android/app/src/main/AndroidManifest.xml`](android/app/src/main/AndroidManifest.xml) and add the following required permissions inside the `<manifest>` tag, directly above the `<application>` block:

```xml
<manifest xmlns:android="http://schemas.android.com/apk/res/android">
    <!-- Internet is standard and required -->
    <uses-permission android:name="android.permission.INTERNET" />
    
    <!-- Required for geolocator -->
    <uses-permission android:name="android.permission.ACCESS_FINE_LOCATION" />
    <uses-permission android:name="android.permission.ACCESS_COARSE_LOCATION" />
```

### iOS Setup 
First, describe why you need permissions. Open [`ios/Runner/Info.plist`](ios/Runner/Info.plist) and add the following inside the main `<dict>` block:

```xml
<dict>
    ...
    <!-- Required for geolocator -->
    <key>NSLocationWhenInUseUsageDescription</key>
    <string>Your current location verifies attendance at the office.</string>
    <key>NSCameraUsageDescription</key>
    <string>Take a fresh photo of your location as attendance evidence.</string>
    <key>NSPhotoLibraryUsageDescription</key>
    <string>Camera images are used only as attendance evidence.</string>
</dict>
```

**IMPORTANT: Podfile Configuration**
Since you've enabled `permission_handler`, you **MUST** configure your requested iOS permissions using Podfile macros to comply with App Store rules. 

Open [`ios/Podfile`](ios/Podfile), find the `post_install` block at the bottom, and replace it completely with this snippet:

```ruby
post_install do |installer|
  installer.pods_project.targets.each do |target|
    flutter_additional_ios_build_settings(target)

    target.build_configurations.each do |config|
      config.build_settings['GCC_PREPROCESSOR_DEFINITIONS'] ||= [
        '$(inherited)',

        ## dart: PermissionGroup.camera
        'PERMISSION_CAMERA=0',

        ## dart: PermissionGroup.photos
        'PERMISSION_PHOTOS=0',

        ## dart: PermissionGroup.location
        'PERMISSION_LOCATION=1',

        ## dart: PermissionGroup.mediaLibrary
        'PERMISSION_MEDIA_LIBRARY=0',

        ## dart: PermissionGroup.microphone (Usually 1 if video recording is active with image_picker)
        'PERMISSION_MICROPHONE=0',

        ## Unused permissions forcefully disabled to avoid App Store Rejection
        'PERMISSION_EVENTS=0',
        'PERMISSION_EVENTS_FULL_ACCESS=0',
        'PERMISSION_REMINDERS=0',
        'PERMISSION_CONTACTS=0',
        'PERMISSION_SPEECH_RECOGNIZER=0',
        'PERMISSION_NOTIFICATIONS=0',
        'PERMISSION_SENSORS=0',
        'PERMISSION_BLUETOOTH=0',
        'PERMISSION_APP_TRACKING_TRANSPARENCY=0',
        'PERMISSION_CRITICAL_ALERTS=0',
        'PERMISSION_ASSISTANT=0',
      ]
    end
  end
end
```

---

Attendance monitoring now requires background location for open attendance. The checked-in `ios/Podfile` enables `PERMISSION_LOCATION=1`; do not set `BYPASS_PERMISSION_LOCATION_ALWAYS=1`. The runner plist contains Always usage text and the `location` background mode. On the Mac build host, run `flutter pub get`, `cd ios`, and `pod install`; verify Runner's Background Modes → Location updates capability and signing in Xcode. Android includes background/foreground-service location and notification permissions, a location notification icon, and notification-plugin desugaring. Grant foreground precise location first, then Always / Allow all the time through the explained on-duty action. Android 11+ can direct the employee to app settings for background access. Camera capture uses the existing native handling; gallery selection is not offered. See [LOCATION-DEVICE-CHECKS.md](LOCATION-DEVICE-CHECKS.md) for platform limits and acceptance checks.

## 5. 🌍 Environment Variables

The app uses `flutter_dotenv` for API configuration. Bundled environment values are readable from the app package; keep credentials and session tokens out of this file.

1. Create a [`.env`](.env) file in the project root folder.
2. Set `API_BASE_URL` to your local or production backend URL (server URL or URL ending in `/api`; the client adds the prefix once) (e.g. `API_BASE_URL=https://api.example.com/api`). On a physical phone, use a reachable host or forwarded HTTPS address rather than `localhost`. You can copy `.env.example` to `.env` as a starting point.
3. The app loads `.env` before initializing the shared Dio client, which reads `API_BASE_URL`. After changing the URL, stop and rerun the app so the updated asset is loaded. Rebuild release apps to include the updated value.

---

## 6. 💾 Local Storage (Hive)

*(No local storage (Hive) selected for this project)*

---

## 7. ☁️ Backend Connections

You chose to structure your APIs using **Custom Backend**.

Verify that your Base URL pointing to staging/production is correctly initialized inside your globally injected network class.
The shared network client in `lib/src/config/app_config.dart` reads `API_BASE_URL` from `.env`.

For the isolated authentication REST test, see the employee authentication section in [README.md](README.md). Use a throwaway backend/database; the test changes its synthetic employee's password and revokes sessions.

---

## Android release signing and Google Play

Release builds use the upload keystore referenced by the private, Git-ignored
`android/key.properties`. Debug builds keep the normal Android debug key.
Never commit or share `key.properties` or the keystore.

On this workstation the upload key and a copy of its properties are in
`C:\Users\Dark Energy\.android\hodour-signing\`. Back up both files together to
a secure location outside this computer. The public certificate is exported to
`output/release/hodour-upload-certificate.pem`; it contains no private key.

Before public release, replace the temporary tunnel URL in `.env` with the
permanent HTTPS backend, then rebuild. Bundled environment values are readable
from the app; they must never contain credentials.

```powershell
flutter pub get
flutter analyze
flutter test
flutter build appbundle --release
```

The signed bundle is `build/app/outputs/bundle/release/app-release.aab`.
If this Windows workstation reports `Unable to establish loopback connection`,
use its existing short temporary directory for Java's local sockets before building:

```powershell
$env:JAVA_TOOL_OPTIONS = '-Djdk.net.unixdomain.tmpdir=C:/tmp'
flutter build appbundle --release
```

Android application ID: `com.wsc.hodour`. Initial version: `1.0.0+1` in `pubspec.yaml`.
Increment the build number for every subsequent Play upload, for example
`flutter build appbundle --release --build-number=2`.

In Google Play Console, create/select Hodour, start with **Internal testing**,
create a release, enroll in **Play App Signing** using Google's generated app
signing key, and upload the signed `.aab`. Keep this local key as the upload key.
Complete the store listing, privacy policy, Data safety, app access instructions
and reviewer login, content rating, and the declarations for background location
and foreground services as prompted. Use actual app/backend behavior for all
answers. Public launch must wait for the permanent backend and device checks in
[LOCATION-DEVICE-CHECKS.md](LOCATION-DEVICE-CHECKS.md).

References: [Flutter Android release guide](https://docs.flutter.dev/deployment/android),
[Play target API requirements](https://support.google.com/googleplay/android-developer/answer/11926878),
[background location declaration](https://support.google.com/googleplay/android-developer/answer/9799150).

## 8. 🚀 Running the App

Once everything above is verified:

1. **For iOS Simulators/Devices**, map your native pods locally:
```bash
cd ios
pod install
cd ..
```

2. Run your app via VS Code, Android Studio, or CLI:
```bash
flutter run
```

Congratulations, and happy coding!


## Multi-company mobile sign-in

Every login requires the company code provided by HR (`workspace`), email and password.
No email-domain inference or default workspace is used. The shared client sends REST
requests beneath one `/api` prefix. Use a phone-reachable LAN host (for example
`http://192.168.1.10:3002/api`, with explicit backend LAN binding) or a forwarded
HTTPS development URL; release builds require HTTPS and normal certificate validation.
Do not put account passwords, tokens, or a default company in the bundled environment.

Account changes clear local access before attempting the new login. Failed new
credentials leave the previous account signed out. Protected 401 ends the session;
403 from a business action checks `/auth/me`, retaining access if that check succeeds
or has a network failure. Rejected `/auth/me` ends access. Password verification retains
its separate 401 handling. Private attendance previews remain memory-only, never URL
credentials or disk image caches. Request attachments remain inline authenticated JSON;
PDF export is an explicit employee save action, outside transient preview retention.

The backend must return company identity/workspace and the employee's assigned-branch
policy. No branch selection, company switching UI, owner APIs, or offline attendance
queue is added. Attendance records retain returned branch names, work dates, shift and
timezone snapshots; policy is refreshed before each capture. The location monitor
follows only the current workday's owned open interval. Older unresolved intervals use
the existing forgotten-checkout workflow, not a new off-duty monitoring session.

For disposable integration fixtures, pass `--dart-define=TEST_WORKSPACE=<fixture-code>`
to Flutter backend tests. Fixture REST logins must also include that same workspace.
The adjacent backend's current test fixture needs a disposable PostgreSQL cluster via
`HR_PG_TEST_ADMIN_URL`; its older in-memory harnesses are not multi-company acceptance.
See `LOCATION-DEVICE-CHECKS.md` for Android/iOS permissions, lifecycle limits and pilot.

## Build on a Mac

After pulling `main`, create the ignored local config with `cp .env.example .env`
and set `API_BASE_URL=https://hr.wallstreetwsc.com/api`. Never copy server Firebase
Admin keys into the app. Run `flutter pub get`, then `cd ios && pod install`.
Open `Runner.xcworkspace` in Xcode and select your Apple development team/signing
for `com.wallstreetwsc.hodour`. The iOS deployment target is 15.0 to match the installed
Firebase Core SDK. Build with Xcode, or return to the repository root and use
`flutter build ios` once signing is configured. iOS push/APNs setup is still
deferred; Android push configuration does not enable iOS notifications.

## Android Firebase Cloud Messaging

See [FCM-ANDROID.md](FCM-ANDROID.md) for Firebase Console device-token tests,
foreground/background behavior, and the remaining backend integration. Android
push is enabled independently of the deferred iOS/APNs setup.
