# hotline-macos-capture

Sends the secure calls of chosen apps on a Mac to a local [Hotline](https://github.com/petercipov/hotline) proxy. A small Swift app installs a macOS system extension (a program macOS runs for the Mac's network traffic). The extension finds which program made each connection and, if the program is on the app list, hands the connection to Hotline over a local socket.

Apple Silicon only, macOS 13 or newer.

**Status: first draft, never built.** It was written without a Mac. Nothing here has been compiled or run yet. See `CLAUDE.md` for the rules and `docs/protocol.md` for the contract with Hotline.

## Layout

- `Sources/CaptureCore`: the app list and the socket messages. All logic, fully unit tested.
- `Extension/`: the system extension (thin layer over macOS).
- `App/`: the helper app that installs the extension (thin layer).
- `project.yml`: Xcode project description for XcodeGen.
- `scripts/build-release.sh`: build, sign, notarize and pack, on a Mac.

## Try the tests (on a Mac)

```
swift test --enable-code-coverage
```

## Build the app (on a Mac)

```
brew install xcodegen
xcodegen
open HotlineCapture.xcodeproj
```

Set your Apple team id in `project.yml` (or pass `DEVELOPMENT_TEAM`). Signing and running the extension needs a paid Apple developer account with the Network Extension permission.

## Checklist for the first run on a Mac

1. `swift test` passes and coverage of `CaptureCore` is at least 90 percent.
2. `xcodegen` makes a project and it builds. Fix project settings that Apple's tools reject.
3. The app refuses to start without a path, and with a path in a shared folder.
4. With a test listener on a private socket: macOS asks for approval once, the extension connects as `control`, and a `SpecUpdate` changes what is captured.
5. A chosen app (for example `curl`) shows up as a `flow` connection with the right destination and program. Another app does not.
6. Stopping leaves the extension installed. Starting again asks for no second approval.

## Thanks

The design (system extension, control connection plus one connection per captured connection, app list with skip rules) follows [mitmproxy_rs](https://github.com/mitmproxy/mitmproxy_rs), MIT licensed. The code here is written fresh.

## Licence

Apache 2.0, see `LICENSE`.
