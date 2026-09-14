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
  (`POST /sessions/draft` + an initial message).
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
  to reach it (URLSession + a plain `Host` header, since the Mac terminates
  Barry's Caddy routing on hostname, and a secret in the keychain). No
  auto-discovery: you tell it where the Mac is once, in Settings.
- `BarrySocket.swift` — the WebSocket layer, explicitly a UX accelerant,
  never a data source. If it never connects, the app still fully works —
  slower, on the poll interval.
- `ChatStore.swift` / `AppStore.swift` — `@MainActor` `ObservableObject`s;
  one per session, one for the app. No Combine beyond `@Published`.
- `Views/` — four screens: sessions list, chat, new-session sheet, settings.

## Reaching the Mac

- **Simulator** (dev): talks straight to `http://127.0.0.1:9429`, the
  barry.works proxy already running locally. No config needed.
- **Real device**: needs the Mac's Tailscale IP and the `barry.lan` host
  header (Caddy's `barry.works`/`barry.lan` site blocks share one proxy;
  routing is by `Host:`, not path) — set both in Settings. A device on the
  same tailnet is trusted network and doesn't need a secret; off-tailnet
  needs the shared `BARRY_SECRET` too (see `packages/auth` in the main
  repo for the trust rules this mirrors).

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
