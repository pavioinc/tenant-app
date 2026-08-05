# NivasaOS Tenant App

Flutter renter mobile app, built against the NivasaOS design system
(`design_handoff_nivasaos/`) and talking to api-gateway only — same principle as
owner-dashboard, no direct backend-service calls.

## Sign-up model

Renters are **not** created by a property manager first. Signup is a general,
standalone NivasaOS platform account:

1. A renter opens the app and creates an account with **full name, email, and
   password** (`SignupScreen` → `POST /api/auth/v1/tenant/signup`) — no phone/OTP
   involved at all.
2. The home screen shows immediately, with a "connect with your property manager"
   prompt, since a fresh account has no property yet.
3. Once a property manager adds a `tenants` row with this same email via
   tenant-service, the app **connects automatically** — no code to enter, no manual
   link step. See auth-service's README ("Tenant accounts vs. tenants") for the
   backend side of this.

Connection status is never cached client-side beyond the current session. The home
screen re-checks it once, silently, on load (`AuthRepository.refreshConnectionStatus`),
and offers a manual "Check again" button as a fallback — pull-to-refresh does the same
thing.

## Architecture

- `lib/core/api_client.dart` — thin HTTP wrapper around api-gateway. Accepts an
  optional bearer `token` per request; signup/login/refresh are public, `GET
  /tenant/me` requires it.
- `lib/core/session_store.dart` — `TenantUser`/`Session` models and secure-storage
  persistence (`flutter_secure_storage`, not `SharedPreferences` — tokens don't belong
  in plaintext).
- `lib/features/auth/` — `SignupScreen`, `LoginScreen`, `AuthRepository` (signup,
  login, `refreshConnectionStatus`, logout).
- `lib/features/home/home_screen.dart` — the renter's nav shell: always visible
  regardless of connection status, with a connect-prompt banner and locked/disabled
  menu tiles (Pay Rent, Complaints, Renewal, Profile) when unconnected. Those four
  screens aren't built yet — tapping a tile says so rather than pretending to work.
- `lib/theme/` — design tokens ported by hand from `design_handoff_nivasaos/`, the
  same source `owner-dashboard/app/tokens.css` encodes for the web. No shared package
  between Dart and TypeScript; keep both in sync manually.

Fonts (Noto Sans, Noto Sans Mono) are bundled as local assets, not fetched from a font
CDN at runtime — required for an offline-first tenant app.

## Local development

```bash
flutter pub get
flutter run -d web-server --web-port=8765 --dart-define=API_BASE_URL=http://localhost:4000
```

`API_BASE_URL` defaults to `http://localhost:4000` (`http://10.0.2.2:4000` on the
Android emulator). Override it for a physical device or simulator pointed at your
host's LAN IP. Requires api-gateway (and everything behind it) running — see the root
`nivasaos/README.md`.

No Android SDK or full Xcode is assumed to be installed; the web target
(`flutter run -d web-server`) is the lowest-friction way to validate changes in a
browser.

## Tests

```bash
flutter analyze
flutter test
```

Widget tests use `package:http/testing.dart`'s `MockClient` (no real network calls)
and an in-memory fake implementing `SecureStore` (no platform-channel calls to the
real secure storage). Covers: signup/login validation and error surfacing, the
unconnected → connected transition (including the silent on-load check picking up a
connection the renter didn't request), locked-menu behavior, and logout.
