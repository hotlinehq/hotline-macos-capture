# hotline-macos-capture

Sends the secure calls of chosen apps on a Mac to a local [Hotline](https://github.com/petercipov/hotline) proxy. A small Swift app installs a macOS system extension (a program macOS runs for the Mac's network traffic). The extension finds which program made each connection and, if the program is on the app list, hands the connection to Hotline's `listen.intercept` port on this Mac.

Apple Silicon only, macOS 13 or newer.

## How it works

Hotline (a Go proxy, in [petercipov/hotline](https://github.com/petercipov/hotline)) never starts your apps. You start them as usual, and Hotline picks up the secure calls of the ones you named:

1. Hotline listens on its `listen.intercept` port, on a loopback address, and is told which apps to capture (the `--capture` flag, still to come in Hotline).
2. Hotline starts the helper app with the address of that port, such as `127.0.0.1:8444`. The helper app installs the system extension and switches it on. The first time, macOS asks you to approve it in System Settings.
3. The extension connects to Hotline as the `control` connection and receives the app list. For each new connection of a listed app it opens a `flow` connection to Hotline, says where the app really called and which program it was, then copies the bytes both ways. Other apps are left alone.

The helper app and the extension refuse an address that is not on this Mac. The exact messages are in `docs/protocol.md`.

## Status

- The code builds and its unit tests pass on a GitHub macOS runner (90 percent coverage of `CaptureCore`), and releases are signed, notarized and published from a version tag. See `docs/release-setup.md`.
- The signed app of release v0.1.0 has been checked on a Mac: the checksum matches, the signature is valid, and macOS accepts it as notarized.
- The extension has not yet been installed, approved or given a connection on a real Mac, and Hotline's `--capture` flag does not exist yet. The Hotline side that takes the connections is `listen.intercept` with `Options.CaptureApps`.

See `CLAUDE.md` for the working rules.

## Layout

- `Sources/CaptureCore`: the app list, the messages to Hotline and the address check. All logic, fully unit tested.
- `Extension/`: the system extension (thin layer over macOS).
- `App/`: the helper app that installs the extension (thin layer).
- `project.yml`: Xcode project description for XcodeGen.
- `scripts/build-release.sh`: build, sign, notarize and pack (used by the release workflow).
- `.github/workflows/ci.yml`: tests, coverage check and unsigned build on every pull request.
- `.github/workflows/release.yml` and `docs/release-setup.md`: signed release on a version tag.

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

## Known doubts to settle on the first real run

- The helper app is a plain program with a run loop, not a full Cocoa application. macOS may insist on one before it shows the approval prompt. If activation hangs or fails with no prompt, switch `App/main.swift` to an `NSApplication` based start.
- `project.yml` (XcodeGen) may need small changes for embedding the extension under `Contents/Library/SystemExtensions`.
- `NWHostEndpoint` is marked deprecated in newer macOS versions. It still works and only gives a build warning.

## Try it by hand (on a Mac)

`scripts/try-capture.py` stands in for Hotline: it answers the extension's control connection with an app list and prints each captured connection. It needs only the Python 3 that macOS brings with its developer tools.

1. Download `HotlineCapture.app.tar` and its `.sha256` file from the [latest release](https://github.com/petercipov/hotline-macos-capture/releases/latest), check them with `shasum -a 256 -c HotlineCapture.app.tar.sha256`, and unpack the tar in `/Applications` (macOS installs system extensions only from there).
2. In one terminal, start the stand-in: `python3 scripts/try-capture.py --apps curl`. It listens on `127.0.0.1:8444`; `--listen sock:///tmp/capture/capture.sock` uses a socket file instead, in a folder you own with mode 0700.
3. In a second terminal, start the helper app with the same address: `"/Applications/Hotline Capture.app/Contents/MacOS/Hotline Capture" 127.0.0.1:8444`. The first time, macOS asks you to approve the extension in System Settings, Privacy and Security. Approve it and the helper app finishes.
4. The stand-in prints `control connection from the extension` and the app list it sent.
5. In a third terminal run `curl https://example.com`. The stand-in prints `captured: example.com:443 from process ... /usr/bin/curl` and that the first byte is `0x16`. The curl call itself then fails, because the stand-in does not answer. Other programs keep working.
6. Stop the stand-in with Ctrl-C. The extension stops capturing.

## Checklist for the first real run on a Mac

1. `swift test` passes and coverage of `CaptureCore` is at least 90 percent.
2. `xcodegen` makes a project and it builds. Fix project settings that Apple's tools reject.
3. The app refuses to start without an address, and with an address that is not on this Mac (for example `0.0.0.0:8444`).
4. With a test listener, either a loopback port (`127.0.0.1:8444`) or a socket file (`sock:///tmp/capture/capture.sock`, in a folder you own with mode 0700): macOS asks for approval once, the extension connects as `control`, and it receives the app list the listener sends.
5. A chosen app (for example `curl`) shows up as a `flow` connection with the right destination and program. Another app does not.
6. Stopping leaves the extension installed. Starting again asks for no second approval.

## Thanks

The design (system extension, control connection plus one connection per captured connection, app list with skip rules) follows [mitmproxy_rs](https://github.com/mitmproxy/mitmproxy_rs), MIT licensed. The code here is written fresh.

## Licence

Apache 2.0, see `LICENSE`.
