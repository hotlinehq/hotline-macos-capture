# hotline-macos-capture

Sends the secure calls of chosen apps on a Mac to a local [Hotline](https://github.com/petercipov/hotline) proxy. A small Swift app installs a macOS system extension (a program macOS runs for the Mac's network traffic). The extension finds which program made each connection and, if the program is on the app list, hands the connection to Hotline's proxy port on this Mac as a standard HTTP CONNECT.

Apple Silicon only, macOS 13 or newer.

## How it works

Hotline (a Go proxy, in [petercipov/hotline](https://github.com/petercipov/hotline)) never starts your apps. You start them as usual, and Hotline picks up the secure calls of the ones you named:

1. Hotline is told which apps to capture (the `--capture` flag, still to come in Hotline).
2. Hotline starts the helper app with its proxy address and that list, such as `127.0.0.1:8080 curl firefox`. The helper app installs the system extension, saves the list in the macOS proxy setting and switches capture on. The first time, macOS asks you to approve the extension in System Settings.
3. For each new connection of a listed app, the extension sends Hotline a CONNECT to where the app really called, with the program in two headers, then copies the bytes both ways. Other apps are left alone.
4. Every 2 seconds the extension checks that Hotline still answers. If it does not, apps go out as usual.
5. When Hotline stops, it runs the helper app with `--stop`. The extension stays installed.

The helper app and the extension refuse an address that is not on this Mac. The exact requests are in `docs/protocol.md`.

## Status

- The code builds and its unit tests pass on a GitHub macOS runner (90 percent coverage of `CaptureCore`), and releases are signed, notarized and published from a version tag. See `docs/release-setup.md`.
- The signed app of release v0.1.0 has been checked on a Mac: the checksum matches, the signature is valid, and macOS accepts it as notarized.
- Release v0.1.1 ran on a real Mac with the earlier message format: the extension was approved, picked out `curl` and handed its connections over. The CONNECT version has not run on a Mac yet.
- Hotline's `--capture` flag and its handling of the capture headers do not exist yet.

See `CLAUDE.md` for the working rules.

## Layout

- `Sources/CaptureCore`: the app list, the CONNECT request and reply, the helper's arguments and the address check. All logic, fully unit tested.
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

`scripts/try-capture.py` stands in for Hotline: it answers the extension's CONNECT requests and prints each captured connection. It needs only the Python 3 that macOS brings with its developer tools.

1. Download `HotlineCapture.app.tar` and its `.sha256` file from the [latest release](https://github.com/petercipov/hotline-macos-capture/releases/latest), check them with `shasum -a 256 -c HotlineCapture.app.tar.sha256`, and unpack the tar in `/Applications` (macOS installs system extensions only from there).
2. In one terminal, start the stand-in: `python3 scripts/try-capture.py`. It listens on `127.0.0.1:8080`.
3. In a second terminal, start capture of `curl`: `"/Applications/Hotline Capture.app/Contents/MacOS/Hotline Capture" 127.0.0.1:8080 curl`. The first time, macOS asks you to approve the extension in System Settings, Privacy and Security. The helper app finishes once capture is on, or says why not.
4. Run `curl https://example.com`. The stand-in prints `captured: ...:443 from process ... /usr/bin/curl` and that the first byte is `0x16`. The curl call itself then fails, because the stand-in does not answer. Other programs keep working.
5. Stop the stand-in with Ctrl-C and run `curl` again within a few seconds: it works, because the extension sees that Hotline is gone.
6. Switch capture off: `"/Applications/Hotline Capture.app/Contents/MacOS/Hotline Capture" --stop`.

## Checklist for the first real run on a Mac

1. `swift test` passes and coverage of `CaptureCore` is at least 90 percent.
2. The helper refuses no arguments, an address without apps, and an address that is not on this Mac (for example `0.0.0.0:8080`).
3. Without the stand-in running, starting capture fails with a message naming the address, and nothing is captured.
4. With the stand-in: `curl` shows up with the right destination, process number and program. Another app does not.
5. Starting again with another list (for example `firefox`) captures the new app and no longer `curl`, with no second approval.
6. With the stand-in stopped, `curl` works again within 2 seconds.
7. `--stop` switches capture off and leaves the extension installed.

## Thanks

The design (system extension, one connection to the proxy per captured connection, app list with skip rules) follows [mitmproxy_rs](https://github.com/mitmproxy/mitmproxy_rs), MIT licensed. The code here is written fresh.

## Licence

Apache 2.0, see `LICENSE`.
