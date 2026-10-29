# Design system — Hodour

This file documents the shared design conventions. Consult it before changing UI code.

---

## Theme overview

- **Preset:** `material3`
- **Material 3:** Primary app chrome uses Material 3 theming in `lib/src/theme/theme.dart`.
- **Dark mode:** Light and dark themes are supported; app can follow system brightness. Use semantic colors — do not branch on brightness in widgets for basic surfaces.
- **Customization:** Global `ThemeData` lives in `lib/src/theme/theme.dart` — avoid one-off `ThemeData` overrides in feature widgets.

- **Light palette:** blue `#0068DC`, pale blue `#C8E7FF`, background `#F7F9FC`, and navy dock `#17263D`. Dark mode uses a navy canvas and lighter blue actions.
- **Seed color:** `#0068DC` (used to derive `ColorScheme` via `ColorScheme.fromSeed` where applicable).

---

## Color system

- Use `context.colors` (`ColorScheme`) for standard Material roles: `primary`, `onPrimary`, `secondary`, `surface`, `onSurface`, `error`, etc.
- Use `context.appColors` for semantic extensions: `success`, `warning`, `info`, and their `on*` / container variants (see `lib/src/theme/color_schemes.dart`).
- Definitions: `lib/src/theme/color_schemes.dart`, applied through `lib/src/theme/theme.dart`.
- **Do not** hardcode hex colors in widgets — use theme roles or `appColors`.

---

## Typography

- Use `context.textTheme` (alias `context.typography`) for all text styles.
- Roles follow Material 3: `display*`, `headline*`, `title*`, `body*`, `label*`.
- No custom fonts uploaded — platform default typography (Roboto / SF Pro) via Material/Cupertino theme.

---

## Spacing, borders, motion

Import tokens via `package:hodour/src/theme/theme_constants.dart`.

| Token class | Purpose |
|-------------|---------|
| `AppSpacing` | Padding, gaps (`xxs` … `xxxl`, plus `pagePadding`, `itemGap`, `cardPadding`) |
| `AppBorders` | Border radii (`xs` … `xl`, `button`, `card`, `input`, `dialog`, …) |
| `AppShadows` | Elevation shadows (`none`, `subtle`, `card`, `elevated`, `modal`) |
| `AppDurations` | Animation durations (`fast`, `normal`, `medium`, `slow`, …) |
| `AppCurves` | Standard curves (`standard`, `emphasized`, `pageEnter`, …) |

**Rules**

- Do not use magic numbers for padding — use `AppSpacing`.
- Do not use inline `BorderRadius.circular(n)` — use `AppBorders`.
- Prefer Material 3 tonal elevation on `Card` / `Surface` — custom shadows only via `AppShadows`.

---

## Responsive scaling (ScreenUtil)

- `ScreenUtilInit` is already applied in the app wrapper — do not add another.
- Design size baseline: **390×844** (iPhone 14 class).
- In templates and new code, use the `res` convention: widths `.w`, heights `.h`, radius `.r`, font sizes `.sp` when ScreenUtil is enabled.
- ScreenUtil values are runtime — avoid `const` widgets that depend on `.w` / `.sp`.

---

## Context extensions

Defined in `lib/src/extensions/context_extension.dart`:

| Member | Use |
|--------|-----|
| `context.colors` | `ColorScheme` |
| `context.textTheme` / `context.typography` | Text styles |
| `context.appColors` | Semantic success/warning/info |
| `context.designTokens` | Theme extension tokens |
| `context.isDarkMode` | Brightness check |
| `context.width` / `context.height` | Screen size |
| `context.showAppDialog` | Dialog helper |
| `context.showTypedSnackBar` | Status snackbars |

Prefer these shortcuts over repeating `Theme.of(context)` in widgets.

---

## Component conventions

- Reusable widgets belong in `lib/src/shared/widgets/`.
- Default style parameters to theme values, not hardcoded colors.
- Widget file names match the widget class (`primary_button.dart` → `PrimaryButton`).
- Do not read theme inside `const` constructors.

### Dark mode checklist

- No raw `Colors.white` / `Colors.black` for surfaces — use `colorScheme` roles.
- Verify new screens in both light and dark theme.

---

## Localization

- User-visible strings use `easy_localization` — files in `assets/translations/`.
- Do not hardcode display strings in widgets.
- Add keys to JSON translation files, then run the generate command in **SETUP.md**.
- Use interpolation in JSON — do not concatenate translated strings in Dart.

---

## Do / Don't

**Do**

- `context.colors` / `context.appColors` for color
- `context.textTheme` for typography
- `AppSpacing`, `AppBorders`, `AppShadows`, `AppDurations`, `AppCurves` for layout and motion
- `showAppDialog` and shared widgets for consistent UX

---

## UI component library

Product widgets live under `lib/src/shared/widgets/ui/`.

### Platform style

- Config: `material` (adaptive | material | cupertino)
- Runtime: wrap with `AppPlatformScope`; override per widget via `platform:`
- Helper: `context.isCupertinoUi` / `context.resolveCupertinoUi(platform)`
- Prefer **App\*** widgets over raw `ElevatedButton` / `TextField` / `CupertinoButton`

### App kit (`ui/app/`) — always generated

| Category | Widgets |
|---|---|
| actions | `AppButton`, `AppIconButton`, `AppTextButton`, `AppFab`, `AppSegmentedControl`, `AppToggleGroup`, `AppChip` |
| inputs | `AppTextField`, `AppSearchField`, `AppPasswordField`, `AppTextArea`, `AppOtpField`, `AppCheckbox`, `AppRadio`, `AppSwitch`, `AppSlider`, `AppNumberStepper`, `AppDropdown`, `AppDatePicker`, `AppTimePicker`, `AppRating`, `AppForm` |
| display | `AppCard`, `AppAvatar`, `AppBadge`, `AppListTile`, `AppDivider`, `AppIcon`, `CommonImage`, `AppProgressBar`, `AppCircularProgress`, `AppSkeleton`, `AppTooltip`, `AppExpansionPanel`, `AppTimeline`, `AppDataTable` |
| feedback | `AppLoading`, `AppErrorWidget`, `AppEmptyState`, dialogs/sheets/banner/snack + toast |
| navigation | `AppScaffold`, `AppTopBar`, `AppBottomNavBar`, `AppTabBar`, `AppNavigationDrawer`, `AppPageIndicator` |
| layout | `AppGap`, `AppResponsiveBuilder`, `AppSection` |

Debug gallery: `AppRoutes.uiShowcase` (`/debug/ui-showcase`) in debug builds.

### Design tokens (required)

```dart
AppSpacing.md
AppBorders.card
AppShadows.elevated
AppDurations.normal
AppCurves.standard
context.colors.primary
context.appColors.success
context.textTheme.titleMedium
context.designTokens.paddingMedium
```

**Never** hardcode hex colors or magic spacing numbers in feature UI.

### shadcn kit

Not enabled for this project. Re-generate with shadcn opted in from the UI & Theme step to add `ShadApp` wrappers.

---

**Don't**

- Hardcode hex colors or arbitrary font families in widgets
- Magic padding/radius numbers
- Duplicate theme definitions per screen
- Bypass design tokens for one-off “quick” UI

For agent workflows and architecture boundaries, see **[AGENTS.md](AGENTS.md)**.

## Employee workspace redesign

- Calm, functional corporate style: blue actions, pale blue containers, cool neutral canvas and white cards in light mode. Dark mode uses the corresponding Material semantic roles.
- Use the shared employee navigation for Home, Attendance, Requests, Account and Sales. Forms and details retain a directional, accessible back button.
- Sales uses the same blue actions, pale blue explanatory notices and rounded cards. Label pending, verified and returned activities in text; explain when work counts. Keep registration separate from team verification and provide a month/year selector. Form labels use semantic text colors for readable contrast.
- Landing screens use descriptive headings and one primary action. Home highlights the server-provided date and assigned schedule; no invented attendance statistics.
- Cards use the extra-large radius token; input controls use the large radius token. Headlines use semibold weight, with quieter secondary text.
- Button state transitions use the quick duration and stop animating when the platform requests reduced motion.
- Keep English and Arabic layouts directional, scrollable and compatible with large text.
- Run the workspace navigation widget test for regression checks. Optional screenshot export uses DESIGN_PREVIEWS and DESIGN_FONT_DIR; previews contain test fixtures only.

### Home — Brand Signature

- Company identity and employee greeting sit on a primary-color header; the attendance surface overlaps its lower edge.
- Preserve the existing circular attendance action, ring animations, elapsed-work progress and raised-center navy dock.
- Replace duplicate navigation shortcuts with Needs your attention: missing check-out corrections and department requests the employee can review, derived from existing attendance and managed-request providers.
- Show all-clear only after both sources load successfully; failures offer retry. Refresh managed reviews with pull-to-refresh and foreground resume.
- Keep the team-sales entry available for review-only accounts without an employee profile.


### Home reference alignment

Home uses dedicated `homeBlue`, `onHomeBlue`, `homeProgress` and `homeTrack`
semantic colors with dark-mode variants. Shared actions and containers use this
same blue family; section headers and detail app bars use `homeBlue` with
`onHomeBlue` text and icons across the app.
The blue header shows company identity, a company-timezone greeting, a localized
server workDate, notification dot and an account avatar. The overlapping attendance
surface pairs assigned shift times with current status, then a compact circular action
and elapsed-work ring. The open record's saved shift/timezone remain authoritative.
Theme selection remains on Account. Monitoring warnings and attention workflows remain
available; they may add content beyond the reference's cropped hero.
