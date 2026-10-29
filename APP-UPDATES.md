# Mandatory app updates

Temporarily disabled by default while the app is in store testing. Normal builds
skip the update gate, including startup and foreground checks. To re-enable it
once the store listings are public, build with
`--dart-define=ENABLE_UPDATE_CHECK=true`. The behavior below applies when enabled.

Android and iOS check their public store listing on startup and whenever the
app returns to the foreground. A newer published version blocks all app screens
with an Update now action. Opening the store does not grant access: the installed
version must pass a subsequent check. Failed checks block access and offer retry,
including when offline. Desktop and web skip the store check.

The existing `app_version_update` package uses the installed Android application
ID / iOS bundle ID to find the listing. No Apple numeric ID is required. Set
`APP_STORE_COUNTRY` in `.env` to a storefront where the iOS app is published
(for example `eg` for Egypt); the default is `us`. Rebuild after changing it.

Increase the version name in `pubspec.yaml` for every release that should force
an update (for example `1.0.1+2` to `1.0.2+3`). A build-number-only increase does
not trigger the store version comparison. Publish the release to both stores;
each platform checks its own listing.

Use fully available production releases. Store propagation, regional/device
availability and staged rollouts can mean a listed update is not yet installable
for every employee. Play Store detection depends on the package's listing parser;
an unavailable listing or parser failure displays the retry screen.

This enforcement applies to app builds containing this feature. Older builds
already installed without the gate cannot be forced by this client change;
enforcing those versions requires a backend version policy as well.

Verification: `flutter test test/update_test.dart`, `flutter analyze`, and
`flutter test`. Before release, test a current and an older installed version
against both real store listings, including opening/returning from the store,
offline retry, Arabic, dark mode and large text.
