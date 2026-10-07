# Pavio Tenant App

Flutter renter mobile app, built against the Pavio design system
(`design_handoff_pavio/`) and talking to api-gateway only — same principle as
owner-dashboard, no direct backend-service calls.

## Sign-up model

Renters are **not** created by a property manager first. Signup is a general,
standalone Pavio platform account:

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

  *(The Home screen tiles and screen names described in this section reflect how they
  first shipped. The "Resident Hub redesign" section below describes the current
  structure — My rental/Renewal were later merged into one Lease screen, and Complaints'
  UI is now labeled Maintenance — the code and backend behind them are otherwise
  unchanged from what's described here.)*

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
- `lib/widgets/pavio_stale_banner.dart` — the "Showing saved data from `<time>` — check
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

## Resident Hub redesign (2026-08-18)

The home screen was rebuilt against a reference screenshot the user provided (a
competing property-management app), using only Pavio's existing design tokens — no
new colors, no image assets (none exist in this app; the payment banner below is a
gradient, not a photo).

- **Header**: the old bare "Log out" `TextButton` is gone — a person-icon `IconButton`
  now opens `ProfileScreen`, which itself gained a settings-gear action opening a new
  `lib/features/profile/settings_screen.dart` (just a "Log out" row for now — the
  `AuthRepository.logout()` + `pushAndRemoveUntil`-to-`LoginScreen` logic moved here
  verbatim). No bell/notification icon was added — there's no notification system in
  this app, so it would be a dead affordance.
- **Payment banner**: a static "Pay Rent — Coming soon" gradient card above the grid.
  Deliberately not wired to a real balance — no tenant-facing "amount due" endpoint
  exists anywhere in `billing-service` or `payment-service` (only a billing *profile* —
  rent amount + cycle — not an outstanding-balance figure). Shares its `_MenuItem` with
  the grid's Payments tile, so tapping either goes through the same connected-gating /
  coming-soon logic.
- **Resident Hub grid**: a 2-column `GridView` replacing the old single-column tile
  list — Contacts, Documents, Guest Manager, Maintenance, Lease, Vehicles, Payments.
  Contacts/Documents/Guest Manager/Vehicles have **no backend yet** — same "coming soon"
  placeholder pattern the old Pay Rent tile used, now generalized. Profile is no longer
  a grid tile — it's reachable only via the header icon now.
- **Lease** (`lib/features/lease/lease_screen.dart`, new) — merges the former **My
  rental** and **Renewal** screens into one, reusing both `RentalRepository` and
  `RenewalRepository` completely unchanged (only the screen files were replaced —
  `lib/features/rental/rental_screen.dart` and `lib/features/renewal/renewal_screen.dart`
  are deleted, the repositories are not). Sections top to bottom: Room & bed, Rent,
  Agreement, a "Rental offers" placeholder (named in the user's request, no backend
  behind it), then the Renewal request/history UI, unchanged. Same dual `fetchWithCache`
  pattern the old Renewal screen already had (`rental_info` + `renewal_requests` cache
  keys), same stale-banner and "Reconnect to request a renewal" action-gating.
- **Maintenance**: a **UI relabel only**, not a rename. `ComplaintsScreen`,
  `ComplaintsRepository`, the `Complaint` model, `tenant-service`'s `complaints`
  table/routes, and `owner-dashboard`'s Complaints sidebar view all keep their original
  names — renaming those would've been a purely cosmetic change across backend,
  frontend, and tests for no functional benefit. Only the strings a renter sees changed:
  the AppBar title, the "New request" button/sheet title (was "New complaint"), and the
  empty-state copy.

Verified: `flutter analyze` + `flutter test` (39 tests — net down from 41 since the
former `rental_screen_test.dart`/`renewal_screen_test.dart` files were replaced by one
consolidated `test/features/lease/lease_screen_test.dart`, plus a new
`settings_screen_test.dart`), and a live, deleted-after-use integration test hitting the
real docker-compose stack as the seeded `amit@example.com` tenant, confirming
`RentalRepository`/`RenewalRepository` — the exact calls `LeaseScreen` makes — return
correct data post-merge. `LeaseScreen`'s actual on-screen rendering is not independently
live-verified beyond that (no way to make a real network call from inside a
`testWidgets()` test — `TestWidgetsFlutterBinding` intercepts `dart:io`'s `HttpClient`
globally and synthesizes a 400 for anything not going through a mocked `http.Client`,
confirmed the hard way on a first attempt) — the mocked widget-test suite covers
rendering correctness instead.

Every backend-touching change here is zero: this arc changed **no backend files** —
purely Flutter UI/navigation.

## Real backends for Contacts, Vehicles, Guest Manager, Documents (2026-08-18)

Direct follow-up to the Resident Hub redesign — the four non-Payments placeholder
tiles all got real `tenant-service` backends and full Flutter screens this pass
(Payments is its own, larger arc — see the section below). No new microservice: all
four are natural extensions of `tenant-service`'s existing `src/routes/tenantSelf.ts`
ownership-scoped self-service pattern (see `tenant-service/README.md` for the backend
side of each).

- **Contacts** (`lib/features/contacts/`) — read-only list of the org's managers/
  owners (name, email, phone), from the new `GET /tenant/me/contacts`. No new
  dependency; phone/email are shown as plain text, not tap-to-call/email (would need
  `url_launcher`, added in this same pass for Documents but not wired up here too —
  left as a clean, obvious future add rather than bundled in without being asked).
- **Vehicles** (`lib/features/vehicles/`) — add/list/delete, a bottom-sheet form
  (plate number, type, optional color), same shape as the existing Maintenance
  ("Complaints") bottom sheet. Backend: `POST`/`GET /tenant/me/vehicles`, `DELETE
  /tenant/me/vehicles/:vehicleId` — tenant-service's **first ownership-checked
  DELETE** (verifies the row's `tenant_id` before removing it, not just org-scoped).
- **Guest Manager** (`lib/features/guests/`) — add/list/delete expected visitors
  (name, optional phone, visit date via a date picker, optional notes). Same CRUD
  shape as Vehicles. No approval workflow, no notification to the property
  manager — this is tenant recordkeeping, per the user's own description of the tile.
- **Documents** (`lib/features/documents/`) — upload (via `file_picker`, base64-
  encoded client-side same as tenant-service's existing agreement e-sign upload),
  list (metadata only), download (opens a 900s presigned S3 URL via `url_launcher`),
  delete (DB row only — S3 object cleanup is a small, deliberately deferred follow-up,
  matching tenant-service's README). **Two new dependencies** — `file_picker` and
  `url_launcher` — the one phase in this arc where new Flutter deps were unavoidable.
  Both wrapped in thin injectable seams (`lib/core/file_picker_service.dart`,
  `lib/core/url_opener.dart`, same shape as `SecureStore`/`CacheStore`) so widget
  tests can fake the picker's selection and the launched URL instead of touching real
  platform channels.
- All four wired into `home_screen.dart`'s `_menuItems` with real `screenBuilder`s,
  replacing their "coming soon" placeholders; each has its own offline read-cache
  (`fetchWithCache`, same convention as every other screen) and a full mocked test
  suite.

Verified: `flutter analyze`/`flutter test` (63 tests, up from 39) and `tenant-service`
(110 tests, up from 71) both green, plus a live end-to-end pass against the real
docker-compose stack for every new endpoint — including, for Documents, actually
downloading the uploaded bytes back through the presigned URL and confirming they
matched exactly, not just checking for a 200.

## Payments — native Razorpay checkout (2026-08-18)

The fifth and largest piece of the same follow-up arc, built last and given the most
scrutiny since it's the one that moves real money. Per the user's explicit choice
(over a browser-launch alternative): a **native Razorpay Checkout SDK** integration,
not a hosted payment page.

- **Backend** (`payment-service`) — new ownership-scoped `GET /tenant/me/invoices`
  (the caller's own pending invoices + a `total_due` sum) and `POST /tenant/me/orders`
  (creates a real Razorpay order, reusing the exact same order-creation/persistence
  logic the existing manager-facing route already had — refactored into a shared
  `createOrderRecord()` rather than duplicated, with the manager route's own tests
  confirmed still passing unchanged against the refactor). The one thing the tenant
  route adds beyond the manager route: verifying the invoice actually belongs to the
  caller before creating an order against it. **No webhook code changed at all** —
  `payment.captured` confirmation was already correct and is reused as-is. See
  `payment-service/README.md`'s "Tenant-facing payments" section for the full detail,
  including how live verification confirmed the real webhook path without needing an
  actual Razorpay account (a correctly HMAC-signed payload, constructed by hand).
- **`lib/core/razorpay_checkout.dart`** (new) — a `RazorpayCheckout` seam around the
  new `razorpay_flutter` dependency, same shape as `FilePickerService`/`UrlOpener`:
  the real implementation wraps the SDK's `Razorpay()`/`.open()`/event-callback API,
  and widget tests inject a fake that can simulate a success or failure callback
  without touching a real platform channel.
- **`lib/features/payments/`** — lists pending invoices with a total-due summary card
  and a "Pay" button per invoice. Tapping creates an order, then opens the native
  checkout with the returned `order_id`/`key_id`/amount. On the SDK's own success
  callback, the screen shows "Payment submitted — pull to refresh in a moment to
  confirm" rather than assuming success — **the SDK's callback is optimistic, not
  authoritative; payment-service's webhook is the real source of truth**, and
  reconciliation happens asynchronously, same as it always has for the manager-
  collected-payment flow. Same offline read-cache (`fetchWithCache`, cache key
  `'payments_invoices'`) and stale-banner/action-gating treatment as every other
  screen — "Pay" relabels to "Reconnect" and disables while showing stale data.
- **Home screen banner**: now navigates to the real `PaymentsScreen` (it used to be a
  dead "coming soon" tap target) and its subtitle changed from "Coming soon" to "View
  & pay." It still doesn't pre-fetch and show the real `total_due` on the Home screen
  itself — that would mean `HomeScreen` doing its own tenant-specific data fetch on
  load, which nothing else on this screen does today. The real number shows once
  inside `PaymentsScreen`, where it belongs with the rest of that screen's own fetch.
- Every Resident Hub tile now has a real screen — none of the seven are "coming soon"
  placeholders anymore. The `_MenuItem`/`screenBuilder` mechanism itself stays in
  home_screen.dart unchanged for whatever the next unbuilt feature turns out to be.

Verified: `flutter analyze`/`flutter test` (70 tests, up from 63) and `payment-service`
(32 tests, up from 28) both green. Live verification against the real docker-compose
stack necessarily stopped short of actually opening a native checkout sheet (no real
Razorpay account exists in this dev environment — `RAZORPAY_KEY_ID`/`_SECRET` are
unset, so the mock gateway handles order creation) but did confirm, against the seeded
`amit@example.com` tenant's two real pending invoices (₹3,300 total): the invoice list
and its `total_due` sum are correct, order creation succeeds and correctly rejects a
different tenant's invoice id (`404 invoice_not_found`), and — the one that actually
matters — POSTing a hand-signed `payment.captured` webhook payload flips the real
invoice to `paid` and it disappears from the pending list, exercising every line of
backend logic this arc added without needing a live Razorpay account to do it.

## Fixed: "jwt expired" on most view clicks (2026-08-18)

**Root cause**: access tokens live 30 minutes
(auth-service's `ACCESS_TOKEN_TTL_SECONDS`). Every screen's `_load()` called
`AuthRepository.currentSession()` and used whatever access token secure storage had,
with no check on whether it was still valid — `currentSession()` was a pure local
read, nothing more. Once 30 minutes passed, api-gateway's JWT verification started
rejecting every request with `401 {message: "jwt expired"}` (the literal string
`jsonwebtoken` throws — see `api-gateway/src/jwt.ts`), and that message surfaced
straight to the UI on every screen, since nothing anywhere refreshed the token before
use. `HomeScreen`'s existing "check connection" flow (`refreshConnectionStatus`) did
rotate tokens, but only from that one explicit call site, not as something every
screen benefited from.

**Fix**: `Session` now carries `accessTokenExpiresAt` (parsed from `expires_at`,
already returned by signup/login/refresh — nothing new needed server-side),
persisted by `SessionStore`. `AuthRepository.currentSession()` — the one method every
screen already calls — now proactively rotates the token (a real call to `POST
/api/auth/v1/refresh`, using the still-valid 7-day refresh token) whenever the
access token is within 30 seconds of expiring or its expiry is unknown (a session
saved before this fix), before returning it. **No screen had to change** — the fix
lives entirely in `currentSession()`'s contract. Concurrent calls during the same
expiry window share one in-flight refresh (`/refresh` itself rotates the refresh
token, so two simultaneous calls would otherwise make the second one fail with an
"already used" refresh token). If the refresh token itself is rejected (expired past
its 7-day TTL, revoked, etc.) the stored session is cleared so "no active session"
handling takes over cleanly; a network failure *during* the proactive refresh instead
leaves the stale session untouched and propagates the error, so a connectivity
hiccup doesn't force a real logout — same offline-handling posture as the rest of
this app.

Live-verified against the real docker-compose stack (temporary, deleted-after-use
test): logged in for real, then hand-set the stored session's expiry into the past
(reproducing exactly what a session looks like ~30 minutes after login) while
keeping the real refresh token — confirmed `currentSession()` rotated to a new
access token via a real `/refresh` call, and that new token successfully
authenticated a real API call that would otherwise have 401'd.

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
- `lib/core/file_picker_service.dart` / `lib/core/url_opener.dart` — thin injectable
  seams over `file_picker`/`url_launcher`, same shape as `SecureStore`/`CacheStore`,
  used by Documents.
- `lib/core/razorpay_checkout.dart` — same seam shape, over `razorpay_flutter`'s
  native checkout SDK, used by Payments.
- `lib/features/auth/` — `SignupScreen`, `LoginScreen`, `AuthRepository` (signup,
  login, `refreshConnectionStatus`, logout).
- `lib/features/home/home_screen.dart` — the renter's nav shell: always visible
  regardless of connection status, with a connect-prompt banner, a payment banner, and a
  2-column Resident Hub grid, locked/disabled when unconnected. `_MenuItem.screenBuilder`
  is null for tiles not built yet (tapping says so rather than pretending to work) and a
  real widget builder once wired.
- `lib/theme/` — design tokens ported by hand from `design_handoff_pavio/`, the
  same source `owner-dashboard/app/tokens.css` encodes for the web. No shared package
  between Dart and TypeScript; keep both in sync manually.

Fonts (Noto Sans, Noto Sans Mono) are bundled as local assets, not fetched from a font
CDN at runtime — required for an offline-first tenant app.

## Push notifications

`lib/core/push_notifications.dart` wraps Firebase Cloud Messaging (FCM): requests
permission, gets the device's FCM token, and registers it with notification-service
(`POST /api/notification/v1/device-tokens`) — called from `AuthRepository.login()`/
`.signup()` and from `main.dart`'s `_SessionGate` on cold start with an existing
session. `AuthRepository.logout()` unregisters the token first. Every call is
best-effort — a push failure (declined permission, Firebase not configured) never
blocks login/signup/logout. Rent-due reminders are the first event wired to this
channel — see notification-service/src/handlers.ts's `handleRentDueEvent` and
providers.ts's `PushNotificationProvider`.

**Client-side setup is done** (2026-08-23) — Firebase project `nivasaos` exists (its identifiers were intentionally kept through the
Pavio rebrand; the new Pavio app IDs must be registered there and the config files
re-downloaded), and both platforms are wired and verified end to end (real device
build + the native "Would Like to Send You Notifications" permission prompt firing on
both a booted iOS simulator and an Android emulator):

- Android: `android/app/google-services.json` is present. The Google Services Gradle
  plugin is declared with a version in `settings.gradle.kts` (`apply false`) and
  actually applied (no version, no `apply false`) in `android/app/build.gradle.kts` —
  it was previously declared `apply false` in the app module too, which registered the
  plugin but never ran it, so `google-services.json` was never processed. Also added
  `android.permission.POST_NOTIFICATIONS` to `AndroidManifest.xml` — required on
  Android 13+ for `requestPermission()` to actually prompt; without it the permission
  call silently no-ops and push never shows.
- iOS: `ios/Runner/GoogleService-Info.plist` is present and registered in
  `Runner.xcodeproj/project.pbxproj` (PBXFileReference + PBXBuildFile + Resources build
  phase + Runner group — added by hand since the FlutterFire CLI wasn't available and
  needs an interactive `firebase login`; verified with `plutil -lint` after editing).
  This project resolves Firebase via Swift Package Manager (`FlutterGeneratedPluginSwiftPackage`),
  not CocoaPods — `flutter_secure_storage`/`razorpay_flutter` are the only two
  CocoaPods-only plugins here. Firebase's current iOS SDK requires a minimum deployment
  target of 15.0, so `IPHONEOS_DEPLOYMENT_TARGET` was bumped from 13.0 to 15.0 across
  all three build configurations (was blocking the build with a clear "requires minimum
  platform version 15.0" error until fixed).

**Still needed for push to actually deliver in production** (not required for local
dev — see below):

1. In the Firebase console, generate an APNs auth key (Project settings → Cloud
   Messaging → Apple app configuration) and upload it — separate from the
   GoogleService-Info.plist step above, and only needed for real iOS push delivery
   (irrelevant to the simulator, which can't receive real push anyway).
2. On the backend: Project settings → Service accounts → Generate new private key,
   then set notification-service's `FIREBASE_SERVICE_ACCOUNT_JSON` env var to that
   file's contents as a single-line JSON string (see
   `notification-service/.env.example`). Until this is set, notification-service logs
   push sends instead of delivering them — the rest of the app works normally, and this
   is genuinely fine for local dev (see that service's README).

No `lib/firebase_options.dart` exists and none is needed — `Firebase.initializeApp()`
with no arguments relies purely on the native config files above, which is sufficient
for a single-Firebase-project, no-multi-flavor setup like this one.

## Local development

```bash
flutter pub get
flutter run -d web-server --web-port=8765 --dart-define=API_BASE_URL=http://localhost:4000
```

`API_BASE_URL` defaults to `http://localhost:4000` (`http://10.0.2.2:4000` on the
Android emulator). Override it for a physical device or simulator pointed at your
host's LAN IP. Requires api-gateway (and everything behind it) running — see the root
`pavio/README.md`.

No Android SDK or full Xcode is assumed to be installed; the web target
(`flutter run -d web-server`) is the lowest-friction way to validate changes in a
browser.

## Tests

```bash
flutter analyze
flutter test
```

70 tests. Widget tests use `package:http/testing.dart`'s `MockClient` (no real network
calls) and in-memory fakes implementing `SecureStore` and `CacheStore` (no platform-
channel calls to real secure storage or `SharedPreferences`) — every screen test injects
both, even ones not specifically about caching, since the real `SharedPreferences`
platform channel isn't available in the widget-test environment and hangs
`pumpAndSettle` rather than failing fast if a screen falls back to its default. The same
injected-fake pattern extends to `FilePickerService`/`UrlOpener` (Documents) and
`RazorpayCheckout` (Payments) — none of those platform channels exist in the test
sandbox either. Covers: signup/login validation and error surfacing, the unconnected →
connected transition (including the silent on-load check picking up a connection the
renter didn't request), locked-hub-tile behavior, logout (now via `SettingsScreen`),
each built screen's load/save/error states plus its HomeScreen navigation wiring,
`fetchWithCache`'s cache/stale/passthrough behavior in isolation
(`test/core/cached_fetch_test.dart`), each screen's stale-banner rendering from a
pre-seeded cache entry, and — for Payments — order creation opening checkout with the
right amount/key and both the success and failure callback paths.
