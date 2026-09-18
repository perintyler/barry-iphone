# QA — Barry iPhone app

## What's actually verified, and how

This app is a thin client over `servers/api`. The tests deliberately hit the
**real, locally running API** rather than mocking it — a client whose tests
mock the server can drift from the server silently forever. Fixtures in
`Tests/ModelsTests.swift` are pinned to real captured payloads (see the
comment at the top of that file); if the API's JSON shape changes, decoding
tests fail on the shape, and `LiveAPITests` fails on the live endpoint.

| Layer | File | Talks to | What it proves |
|---|---|---|---|
| Decoding | `Tests/ModelsTests.swift` (`ModelsTests`) | nothing (fixtures) | The `Codable` models match the API's real JSON field-for-field |
| Integration | `Tests/ModelsTests.swift` (`LiveAPITests`) | live local API | Sessions/messages/repos endpoints are reachable and decode; sequence numbers are monotonic (the incremental-poll invariant the app relies on) |
| UI, read paths | `UITests/BarryUITests.swift` | live local API, real simulator | Session list renders; opening a session renders its message history and shows a working input bar; Settings' "Test connection" reports a fully working connection |
| Probe | `Tests/ConnectionProbeTests.swift` | `URLError` values, a stub, plus the real :4854 and :9429 | "Test connection" tells its failure modes apart |
| UI, compose path | `UITests/BarryUITests.swift` (`testNewSessionSheetPopulatesFromRealAPI`) | live local API | The repo picker loads real repos and the Start button gates correctly — **does not submit**, on purpose (see below) |
| UI, trait picker | `UITests/BarryUITests.swift` (`testTraitPickerMultiSelect`) | live local API | The trait picker loads the real trait catalog, tapping two rows leaves both checked (filled circle + accent row), and the New Session form's "Traits" row reflects the live count — does not submit |

`LiveAPITests` and the UI tests `XCTSkip` (not fail) if `127.0.0.1:9429` is
unreachable, so CI or a machine without Barry running doesn't get spurious
red — but that also means a genuinely broken app gets a pass with no server
up. Always run with the API reachable before trusting a green run; `scripts/test.sh` warns if it isn't.

## Why no UI test submits a real message or starts a real session

This isn't a sandboxed test fixture — it's the same Postgres/session store
every other Barry session on this machine reads and writes. An automated
test loop that starts real Barry sessions or sends real prompts on every CI
run would spawn live agent runs against a real repo as a side effect of
testing a UI. `testNewSessionSheetPopulatesFromRealAPI` verifies the compose
sheet is wired to the real repo list and that the Start button's enable
logic is correct, then cancels.

## Verified negative controls

Per this repo's standing rule ("a check that cannot fail is worse than no
check"), both the unit and UI layers were confirmed to actually fail on a
real regression, not just pass vacuously:

- Swapped the `isUser`/`isAssistant` role check in `Models.swift` →
  `testDecodesTextAndToolMessages` went red.
- Pointed `BarryClient.sessions()` at a wrong path (guaranteed 404) →
  `testSessionListLoads` went red (`ContentUnavailableView` shown instead of
  the list, exactly as it would for a real user on a real outage).

Both were reverted after confirming red; do this again after any nontrivial
change to `Models.swift` or `BarryClient.swift` — it's the only way to know
a test is exercising the code path it claims to.

## Bug found and fixed during verification

`ChatView`'s original implementation fetched up to 5000 messages on opening
any session and rendered them all into a `LazyVStack`. Real sessions on this
machine run 100–500+ messages; the UI test `testOpensChatAndShowsMessages`
caught this directly — the message input didn't become interactable inside
a 10s timeout when opened against a 400+ message session (confirmed via the
`.xcresult` screen recording, see below). Fixed by loading only the most
recent 60 messages on open (the server already supports this — calling
`GET /messages` with no `before`/`after` returns the most recent page, see
`packages/db/src/messages.ts:718-728` — the client just wasn't asking for
it), with older history paged in on scroll-to-top. Chat-open time on a
400-message session dropped from timing out past 10s to ~2s.

## Debugging a UI test failure

`xcodebuild test` records a full screen recording and UI hierarchy snapshot
for every test. To see exactly what the simulator showed at failure:

```bash
DD=$(ls -d ~/Library/Developer/Xcode/DerivedData/Barry-* | head -1)
XCRESULT=$(ls -td "$DD"/Logs/Test/*.xcresult | head -1)
xcrun xcresulttool export attachments --path "$XCRESULT" \
  --output-path /tmp/xcresult-export \
  --test-id "BarryUITests/testYourFailingTest()"
# Pulls a .mp4 recording + UI hierarchy dump + any XCTAttachment screenshots.
# Grab a frame near the end of the recording:
ffprobe -v error -select_streams v:0 -show_entries stream=nb_frames \
  -of default=nk=1 /tmp/xcresult-export/*.mp4   # get frame count N
ffmpeg -y -i /tmp/xcresult-export/*.mp4 -update 1 -frames:v 1 \
  -vf "select='eq(n\,$((N-5)))'" /tmp/failure-frame.png
```

This is how the message-history bug above was actually diagnosed — the
symptom ("input never appears") looked like a broken accessibility
identifier until the recording showed the real cause (input was there,
just slow to become interactive under a heavy scroll/render load).

## Manual checks (not automatable without a device / real send)

Run these against a physical iPhone before considering a release "done":

- [ ] **Set the secret in Settings.** Unlike the old proxy route, the device
      path 403s without it. "Test connection" says so in those words.
- [ ] **Turn Wi-Fi off.** Over cellular the app must still reach the Mac via
      Tailscale at `https://barry-mac.tail5cb2f2.ts.net:8443`. This is the
      difference between "the app works" and "the simulator's localhost works".
- [ ] "Test connection" with a deliberately wrong host must say it cannot
      RESOLVE the host, not merely "failed" — the point of the probe is that
      wrong-tailnet and server-down do not look alike.
- [ ] Send a real message to a real session; confirm it appears optimistically
      and reconciles with the server's copy once persisted
- [ ] Background the app mid-stream, foreground it — polling should resume
      and catch up (no duplicate or dropped messages)
- [ ] Dark mode — chat bubbles, tool rows, and status colors all stay legible
- [ ] VoiceOver: session rows and the compose sheet read sensibly

## The transport probe's negative controls

Both were run and confirmed red, then reverted.

| # | Check | Break it by | Confirmed result |
|---|---|---|---|
| 1 | a wrong tailnet and a dead sidecar differ | fold `.cannotFindHost` into the `.cannotConnect` case | `testWrongTailnetAndDownSidecarAreDifferentOutcomes` red: `("cannotConnect") is not equal to ("cannotResolveHost")`, and "a wrong tailnet and a dead sidecar must not read identically"; `testDNSFailureIsReportedAsAnUnresolvableHost` red too |
| 2 | an unhealthy server is not blamed on the secret | delete the non-2xx check on `/health` in `ConnectionProbe.run` | `testAnUnhealthyServerIsNotBlamedOnTheSecret` red — the stub answers `/health` with 502 and the sessions route with 403, so without the health check the 403 wins and the probe blames the secret |

The stub in control #2 answers the two routes with **different** statuses on
purpose. A stub returning one status to both would leave the test green even
with the health check deleted, because the sessions call would then produce the
same 502 by itself — the "passing negative control" trap AGENTS.md describes.

## Known-failing UI tests (pre-existing, not transport)

`testGroupedToolRunExpandsAndCollapses`, `testJumpToBottomCanAppearAndBeTapped`
and `testLongUserMessageCollapsesAndExpands` look up specific sessions by name
(`barry-ios-app-setup`) in the live database. Those sessions have aged out of
the first page, so the tests fail on a lookup, not on app behaviour. Confirmed
by running them against the unmodified tree.
