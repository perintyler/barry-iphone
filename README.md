# Barry (iPhone)

A minimal, native iOS chat client for Barry sessions — an alternative to the
barry.works/sessions web view, built for reading and steering sessions from
a phone.

## What it does

- Lists sessions (running first, then by recency), pulling from the same
  `GET /api/v1/sessions` the web app and macOS app use.
- Opens a session as a chat: user turns as bubbles, assistant text as
  markdown, tool calls as quiet one-line rows you tap to expand (full
  input/result, fetched on demand from `/messages/:sequence/detail`).
- Sends follow-up messages (`POST /sessions/:id/message`), which starts the
  session server-side if it isn't already active.
- Starts new sessions against a repo Barry already knows about
  (`POST /sessions/draft` + an initial message), with optional provider,
  model, and trait overrides. Provider choices and each provider's models
  come from `GET /api/v1/models?repoPath=…`; the model picker shows only the selected
  provider's entries, and changing provider clears the previous model.
  When Barry has only a saved list, the picker says so and accepts a model ID
  that is not listed. Traits are picked from the real
  `GET /api/v1/traits` catalog, multi-select, none required.
- Live-ish updates: a WebSocket subscription drives instant streaming
  previews and "poll now" nudges; a REST poll (2.5s) is the source of
  truth, so the app works correctly even for CLI-started sessions the
  WebSocket layer never learns about (see `BarrySocket.swift`).

## Architecture

Deliberately small — no networking library, no state-management framework,
no design system dependency:

- `Models.swift` — `Codable` structs matching the API's real JSON exactly
  (see `Tests/ModelsTests.swift`, which pins fixtures captured from the
  live server).
- `ServerConfig.swift` + `BarryClient.swift` — where the server is and how
  to reach it (URLSession, and a secret in the keychain). The device address
  is a stable tailnet name, so there is nothing to keep current — Settings
  still overrides and persists it.
- `ConnectionProbe.swift` — what "Test connection" actually proved.
- `BarrySocket.swift` — the WebSocket layer, explicitly a UX accelerant,
  never a data source. If it never connects, the app still fully works —
  slower, on the poll interval.
- `ChatStore.swift` / `AppStore.swift` — `@MainActor` `ObservableObject`s;
  one per session, one for the app. No Combine beyond `@Published`.
- `Views/` — four screens: sessions list, chat, new-session sheet, settings
  (new-session also opens provider/model/trait picker sheets).

## Reaching the Mac

Every Barry service binds `127.0.0.1`. There is **no route to a raw service
port** from a phone.

| | Base URL | Secret |
|---|---|---|
| Simulator | `http://127.0.0.1:9429` | not needed — the proxy injects one |
| Device | `https://barry-mac.tail5cb2f2.ts.net:8443` | **required** |

The device path goes over the user's PERSONAL tailnet to a userspace
`tailscaled` sidecar (separate from the Mac's work Tailscale client), which
terminates TLS and proxies to the API on `127.0.0.1:4854`.

**The certificate is a real Let's Encrypt one**, issued for the tailnet name, so
there is no certificate warning on the phone and nothing to pin or trust
manually. That is why the app ships no `NSAllowsArbitraryLoads` — see below.

**The secret is required on the device path.** `:4854` rejects an
unauthenticated caller with 403 *even from loopback*; `/health` is the only open
route. This is the opposite of the old Caddy route, where the barry.works proxy
filled the secret in for trusted-network callers. A phone with no secret set
gets a 403, which "Test connection" reports in those words.

> **This replaces a stale hardcoded IP.** The device default used to be
> `http://100.101.38.91` plus a `Host: barry.lan` header to select a Caddy site
> block. That address is on the WORK tailnet, which the phone is not on, so the
> device path was dead rather than merely out of date. The sidecar's DNS name is
> stable, so there is no address to keep up to date.

### App Transport Security

The app sets **`NSAllowsLocalNetworking`**, not `NSAllowsArbitraryLoads`.

The device path is genuine HTTPS and needs no exception at all. The one
remaining cleartext caller is the *simulator*, which talks to the proxy on
`http://127.0.0.1:9429` — and ATS blocks that unless permitted.
`NSAllowsLocalNetworking` permits exactly loopback and link-local, and nothing
routable, so a misconfigured `http://` tailnet URL still fails loudly instead of
silently downgrading.

### Test connection

Settings probes rather than accepting a string. The user switches tailnets, so
the failures that need different fixes must not collapse into one "failed"
message: **wrong tailnet** (cannot resolve the host), **sidecar down** (resolved
but cannot connect), and **secret wrong** (403 — which still proves the server
is THERE) each get their own wording.

No custom backend was written for this app — it is a client of the existing
`servers/api` sessions/messages/WebSocket surface, the same one
`bags/sessions/sessions-macos` and `bags/barry.works` use.

## Building

Requires Xcode 16+, [XcodeGen](https://github.com/yonaskolb/XcodeGen)
(`brew install xcodegen`), and the local Barry API running
(`barry.works` proxy on `127.0.0.1:9429` — `launchctl list | grep
barry.works`).

```bash
xcodegen generate                 # regenerate Barry.xcodeproj from project.yml
xcodebuild -project Barry.xcodeproj -scheme Barry \
  -destination 'platform=iOS Simulator,name=iPhone 16 Pro' build
```

`Barry.xcodeproj` is gitignored-adjacent but checked in for convenience;
regenerate it with `xcodegen generate` after editing `project.yml` or
adding/removing source files (xcodegen globs `App/`, `Tests/`, `UITests/`
— new files need a regenerate, not just a re-build).

## Testing

See `QA.md` for the full verification story (what's covered, what isn't,
and how to reproduce a UI test failure with a screenshot/video pulled from
the `.xcresult` bundle). Short version:

```bash
./scripts/test.sh
```

runs the full suite (unit + integration-against-the-real-local-API + UI)
against a booted simulator and prints a pass/fail summary. Integration and
UI tests talk to the real, locally running Barry API — they are not
mocked, and they skip (not fail) if the API is unreachable.
