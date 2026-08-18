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

## Building out the real screens (2026-08-14, in progress)

Login was verified working end-to-end against a live backend before starting (signup,
login, refresh/token-rotation, wrong-password rejection, logout — see git history for
the ad-hoc verification, not part of the permanent suite). Home screen's menu tiles are
being wired up one at a time, Pay Rent deliberately last (needs either a native Razorpay
SDK or a browser-launch flow — decision deferred):

- **Profile** (`lib/features/profile/`) — view name/email (read-only) and edit
  phone/language. Backend: `tenant-service`'s new `GET`/`PATCH
  /api/tenants/v1/tenant/me` — the **first ownership-scoped route in the entire
  backend fleet**. Every route anywhere else only checks `X-Org-Id`; this one resolves
  the caller's own `tenants` row from `X-User-Id` and only ever touches that row. See
  `tenant-service/README.md`'s "Tenant self-service" section for the full story,
  including a real discovered gap: no other route in the fleet checks caller identity at
  all, not fixed in this pass — flagged, not silently expanded into scope.
- **My rental** (`lib/features/rental/`, a new tile — not one of the original four) —
  read-only room/bed, rent, and agreement details. Backend: `tenant-service`'s new `GET
  /tenant/me/rental` (aggregates allocation + bed-via-property-service + agreement in
  one call) and `billing-service`'s new `GET /tenant/me/billing-profile`, both following
  the same ownership-scoping pattern Profile established.
- **Renewal** (`lib/features/renewal/`) — shows the current agreement's end date (reuses
  the Rentals fetch), a "Request renewal" action with an optional preferred-end-date
  picker, and the tenant's own request history. Deliberately lightweight: creates a
  `renewal_requests` row and notifies the org's owner by email — a manager still creates
  the actual renewed `rent_agreement` through the existing flow, nothing is
  auto-drafted. Backend: `tenant-service`'s new `POST`/`GET
  /tenant/me/renewal-requests` (a `renewal.requested` SQS event) and
  `notification-service`'s new consumer. Live verification here surfaced a real,
  pre-existing bug unrelated to this arc: the "manager adds a tenant, renter signs up
  afterward" connection order did **not** actually auto-link, despite both this
  README and `tenant-service/README.md` claiming order independence —
  `auth-service`'s tenant-signup "already connected?" check compared by
  `tenant_account_id` (which is brand new at signup time and can't match anything),
  not by email, so it was structurally unable to find a tenant a manager added first.
  **Fixed 2026-08-18** — see `auth-service/README.md`'s "Tenant accounts vs. tenants"
  section — connection order no longer matters either way, and both directions now
  send the renter a notification (a WhatsApp/SMS "you're connected" message, or an
  email invite to sign up, from `tenant-service`'s `POST /tenants`).
- **Complaints** (`lib/features/complaints/`) — own complaints list with a status badge
  and a "New complaint" bottom sheet (category picker + description). Backend:
  `tenant-service`'s new `POST`/`GET /tenant/me/complaints` (ownership-scoped, same
  `tenantSelf.ts` file) plus a manager-facing `GET /complaints` + `PATCH
  /complaints/:id/status` that now has a real `owner-dashboard` list view too (Complaints
  sidebar item) — a complaint nobody can see wouldn't be useful. This closes out the
  four original menu tiles plus the Rentals-view addition; only **Pay Rent** remains,
  deliberately deferred to a later arc.

Every phase was verified two ways beyond `flutter analyze`/`flutter test`: the existing
mocked widget-test suite, and a real, unmocked run against the live docker-compose stack
through the actual api-gateway (a temporary integration test under `test/integration/`,
deleted after each verification — not part of the permanent suite, since it needs a live
backend to pass). This caught a real, non-obvious fact worth knowing: **an unconnected
renter's JWT carries no `org_id` claim at all**, so it can't reach any org-scoped
endpoint via the gateway before a manager links them (`400 missing_org_context`, not
`404`) — a natural security boundary that already existed, not something built here.

## Read-only offline caching (2026-08-18)

The design doc calls out offline-first as this app's top priority (the local font
bundling already reflects that intent). This pass covers **read caching only** —
Profile, My rental, Renewal, and Complaints each persist their last successful API
response and fall back to it, clearly marked, when a fresh fetch fails for a
connectivity reason. Offline **writes** (queuing a submitted complaint or renewal
request while offline, to sync later) are **not built** — Save/Submit still just fail
with a "could not save, try again" message offline, same as before this pass. A future
arc that wants real offline writes needs a queue with conflict/retry handling; this one
deliberately doesn't attempt it.

- `lib/core/cache_store.dart` — `CacheStore` (`SharedPreferences`-backed), the
  non-secret counterpart to `SecureStore`: same seam shape, swappable for an in-memory
  fake in tests, but for cached API responses rather than the auth session.
- `lib/core/cached_fetch.dart` — `fetchWithCache`, the one helper every screen routes
  its load through. On success, caches the response and returns it fresh. On failure, an
  `ApiException` (a real non-2xx response from api-gateway, e.g. a 404 for "not
  connected to a property yet") always propagates untouched — cache never masks a real
  answer. Anything else reaching that catch (`SocketException`, timeout, DNS failure) is
  treated as a genuine connectivity problem, so `fetchWithCache` falls back to the cache
  and marks the result `stale: true` with the original `lastSyncedAt`. No cache entry
  means the original error still surfaces — there's nothing to fall back to.
- `lib/widgets/nivasa_stale_banner.dart` — the "Showing saved data from `<time>` — check
  your connection" banner shown at the top of a screen's content when `stale == true`.
  Pull-to-refresh (already on every one of these screens) is the retry mechanism; there's
  no separate retry button.
- **Action-gating**: Profile's Save and Complaints' Submit stay enabled while showing
  stale data — they already degrade gracefully offline with no queue needed. Renewal's
  "Request renewal" button is the one exception: disabled while stale (label "Reconnect
  to request a renewal"), since the one-pending-request check it relies on could be wrong
  against stale data.

Live-verified against the real docker-compose stack (temporary, deleted-after-use
integration test, same convention as the rest of this file): fetched My rental online as
the seeded `amit@example.com` tenant to populate the cache, re-fetched with the API base
pointed at an unreachable host to confirm the stale banner path renders the same data
with the right `lastSyncedAt`, then fetched again as a brand-new, never-connected tenant
sharing the same cache instance — confirmed the real `400 missing_org_context` response
came through untouched rather than being masked by the other tenant's stale cache entry
sitting under the same key.

## Architecture

- `lib/core/api_client.dart` — thin HTTP wrapper around api-gateway. Accepts an
  optional bearer `token` per request; signup/login/refresh are public, `GET
  /tenant/me` requires it.
- `lib/core/session_store.dart` — `TenantUser`/`Session` models and secure-storage
  persistence (`flutter_secure_storage`, not `SharedPreferences` — tokens don't belong
  in plaintext).
- `lib/core/cache_store.dart` / `lib/core/cached_fetch.dart` — non-secret,
  `SharedPreferences`-backed response caching for the offline read-fallback described
  above.
- `lib/features/auth/` — `SignupScreen`, `LoginScreen`, `AuthRepository` (signup,
  login, `refreshConnectionStatus`, logout).
- `lib/features/home/home_screen.dart` — the renter's nav shell: always visible
  regardless of connection status, with a connect-prompt banner and locked/disabled menu
  tiles when unconnected. `_MenuItem.screenBuilder` is null for screens not built yet
  (tapping says so rather than pretending to work) and a real widget builder once wired.
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

41 tests. Widget tests use `package:http/testing.dart`'s `MockClient` (no real network
calls) and in-memory fakes implementing `SecureStore` and `CacheStore` (no platform-
channel calls to real secure storage or `SharedPreferences`) — every screen test injects
both, even ones not specifically about caching, since the real `SharedPreferences`
platform channel isn't available in the widget-test environment and hangs
`pumpAndSettle` rather than failing fast if a screen falls back to its default. Covers:
signup/login validation and error surfacing, the unconnected → connected transition
(including the silent on-load check picking up a connection the renter didn't request),
locked-menu behavior, logout, each built screen's load/save/error states plus its
HomeScreen navigation wiring, `fetchWithCache`'s cache/stale/passthrough behavior in
isolation (`test/core/cached_fetch_test.dart`), and each screen's stale-banner rendering
from a pre-seeded cache entry.
