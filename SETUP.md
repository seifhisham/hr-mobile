# 🎉 Welcome to hrmobile!

This project was generated dynamically based on your specific requirements. Before running your app for the first time, follow this brief setup guide to configure the required environment variables, permissions, and dependencies locally.

---

## 1. 📱 Platform folders (web download only)

The web wizard ZIP does **not** include native runners (`android/`, `ios/`, `web/`, `windows/`, `macos/`, `linux/`). Those are created only via the Flutter CLI.

Skip this step if you generated the project with the FlutterInit CLI (`flutter create` already ran).

From the project root:
```bash
flutter create . --project-name hrmobile --org com.wsc
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
        'PERMISSION_LOCATION=0',
        'PERMISSION_LOCATION_WHENINUSE=1',

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

For foreground-only attendance location, add `BYPASS_PERMISSION_LOCATION_ALWAYS=1` to the geolocator_apple target's preprocessor macros on the Mac build host, as described in the [geolocator iOS setup](https://pub.dev/packages/geolocator#ios). No background location permission is needed. Camera capture uses image_picker's native permission handling; gallery selection is not offered.

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
