# Hotline Capture (macOS)

A small Swift app with a system extension (a program macOS runs for the Mac's network traffic) that picks out the secure calls of chosen apps and hands them to the Hotline proxy's socket file on this Mac (its `listen.capture`) as a standard HTTP CONNECT. The Hotline proxy itself lives in `petercipov/hotline` and is written in Go. Requirements: `mitmproxy-ideas/wrap-command-requirements.md` in the Hotline project files (decided points are marked there).

## Working rules

- **Ask before building more.** Define requirements with Peter first, then build only after he agrees. The CI workflow (`.github/workflows/ci.yml`) runs on every pull request, as Peter asked. Do not watch or poll checks unless Peter asks.
- **Keep replies compact and plain.** Short sentences, define jargon in plain words, say "ingress" for the ways apps reach the proxy.
- **Never commit secrets.** No certificates, provisioning profiles, Apple ID or passwords. They live only in this repository's secrets and on Peter's machine.

## Scope and layout

- Apple Silicon only, macOS 13 or newer. No Intel build.
- No third-party dependencies. Foundation, Network and NetworkExtension only. This keeps the app small and the signing simple.
- `Sources/CaptureCore`: everything that needs no macOS network APIs (the app list, the CONNECT request and reply, the helper's arguments, the socket path check). All logic goes here.
- `Extension/` and `App/`: thin layers. They only call macOS APIs and `CaptureCore`. If code in them grows a decision, move the decision into `CaptureCore` and test it there.
- `docs/protocol.md` is the contract with the Go proxy. Change it together with `ConnectRequest.swift` and raise `ConnectRequest.captureVersion` when a header changes.

## Test-driven development

1. Write a failing XCTest that describes the behaviour, in `Tests/CaptureCoreTests`.
2. Run `swift test` and confirm it fails for the right reason.
3. Write the least code that passes.
4. Run `swift test` again, then refactor with the tests green.

Test names say the behaviour in plain words (`testOversizedAnnouncementIsRefusedBeforeReadingTheBody`).

## Coverage

- Target: at least 90 percent of lines in `CaptureCore`, and every error path in the request, the reply and the arguments covered.
- CI enforces it with `scripts/check-coverage.sh 90`. Measure by hand with `swift test --enable-code-coverage`, then `xcrun llvm-cov report` on the test bundle. Do not lower the target to make a change pass; add tests.
- `Extension/` and `App/` are not unit tested. Keep them small. Their behaviour is checked by hand on a real Mac, with the checklist in `README.md`.

## Coding standards

- Format with `swift-format` using the repository's `.swift-format` file. Do not hand-format.
- Plain comments that explain why, written for a non-expert. No abbreviations, no clever tricks.
- Errors are typed (`ConnectReply.ReplyError`, `ConnectRequest.RequestError`) and never swallowed. Every external input is untrusted: check size and version before using it.
- The extension must never block the main queue and must never read or change the content of a connection. It only copies bytes.
- Public API of `CaptureCore` stays small. Prefer value types.

## Security rules (from the requirements)

- The extension connects to Hotline's socket file and sends a CONNECT with the capture headers. The path must be absolute and at most 103 bytes (`CapturePath` refuses anything else, in the app and again in the extension). Hotline believes the capture headers only on that socket file, and only from root, as the extension runs; on its proxy port they are ignored (Peter, 2026-11-12). The extension still never hands over loopback connections, to leave local services alone.
- A header value never holds a control character, and a reply over `ConnectReply.maxSize` or not HTTP closes the connection.
- Never capture Hotline's own processes. The helper always adds its caller, Hotline, as a skip rule.
- When Hotline does not answer the 2-second check, capture nothing, so apps keep working.

## Signing and release

- Releases are built, signed, notarized and published by `.github/workflows/release.yml` on a GitHub macOS runner when a `v*` tag is pushed. `scripts/build-release.sh` does the work and can also run on a Mac. One-time setup is in `docs/release-setup.md`. Secrets come from environment variables and repository secrets, never from files in the repository.
- Raise the extension version number on every change, or macOS keeps the old one.
- Release builds are produced on release tags only, never on pull requests from forks.

## Not verified yet

Release v0.1.1 ran on a real Mac with the earlier message format. The CONNECT version, and capture version 2 over the socket file, have not: treat their first run there, with the checklist in `README.md`, as their first real test.
