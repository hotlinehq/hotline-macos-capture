# Hotline Capture (macOS)

A small Swift app with a system extension (a program macOS runs for the Mac's network traffic) that picks out the secure calls of chosen apps and hands them to the Hotline proxy over local sockets. The Hotline proxy itself lives in `petercipov/hotline` and is written in Go. Requirements: `mitmproxy-ideas/wrap-command-requirements.md` in the Hotline project files (decided points are marked there).

## Working rules

- **Ask before building more.** Define requirements with Peter first, then build only after he agrees. Do not start CI runs or watch checks unless Peter asks.
- **Keep replies compact and plain.** Short sentences, define jargon in plain words, say "ingress" for the ways apps reach the proxy.
- **Never commit secrets.** No certificates, provisioning profiles, Apple ID or passwords. They live only in this repository's secrets and on Peter's machine.

## Scope and layout

- Apple Silicon only, macOS 13 or newer. No Intel build.
- No third-party dependencies. Foundation, Network and NetworkExtension only. This keeps the app small and the signing simple.
- `Sources/CaptureCore`: everything that needs no macOS network APIs (the app list, the socket messages, framing). All logic goes here.
- `Extension/` and `App/`: thin layers. They only call macOS APIs and `CaptureCore`. If code in them grows a decision, move the decision into `CaptureCore` and test it there.
- `docs/protocol.md` is the contract with the Go proxy. Change it together with `Messages.swift` and raise `captureProtocolVersion` when a message changes.

## Test-driven development

1. Write a failing XCTest that describes the behaviour, in `Tests/CaptureCoreTests`.
2. Run `swift test` and confirm it fails for the right reason.
3. Write the least code that passes.
4. Run `swift test` again, then refactor with the tests green.

Test names say the behaviour in plain words (`testOversizedAnnouncementIsRefusedBeforeReadingTheBody`).

## Coverage

- Target: at least 90 percent of lines in `CaptureCore`, and every error path in framing and message checking covered.
- Measure with `swift test --enable-code-coverage`, then `xcrun llvm-cov report` on the test bundle. Do not lower the target to make a change pass; add tests.
- `Extension/` and `App/` are not unit tested. Keep them small. Their behaviour is checked by hand on a real Mac, with the checklist in `README.md`.

## Coding standards

- Format with `swift-format` using the repository's `.swift-format` file. Do not hand-format.
- Plain comments that explain why, written for a non-expert. No abbreviations, no clever tricks.
- Errors are typed (`FrameError`) and never swallowed. Every external input is untrusted: check size and version before using it.
- The extension must never block the main queue and must never read or change the content of a connection. It only copies bytes.
- Public API of `CaptureCore` stays small. Prefer value types.

## Security rules (from the requirements)

- Sockets live in a private folder with a random name, open only to the user and root. The Go proxy creates them; this app only connects.
- Refuse any message with an unknown version or a size over `Framing.maxFrameSize`.
- Never capture Hotline's own processes. The app list from the proxy always skips them.

## Signing and release

- Signing, notarizing and publishing are done on a macOS machine with `scripts/build-release.sh`. Secrets come from environment variables, never from files in the repository.
- Raise the extension version number on every change, or macOS keeps the old one.
- Release builds are produced on release tags only, never on pull requests from forks.

## Not verified yet

The Swift code was written without a Mac to compile on. Treat the first build on a Mac as the first real test, and fix what it finds before trusting any of it.
