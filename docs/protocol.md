# How the extension talks to Hotline (capture version 2)

This is the contract between this app and the Hotline proxy (Go, in `petercipov/hotline`). It is plain HTTP: a CONNECT request with a `User-Agent` and three headers of ours. Change this file together with `Sources/CaptureCore/ConnectRequest.swift`, and raise `ConnectRequest.captureVersion` when a header, or the way it reaches Hotline, changes. Version 2 (2026-11-12) moved the CONNECT from Hotline's proxy port to a socket file; the headers are the same as in version 1.

## Starting and stopping

Hotline runs the helper app:

- `Hotline Capture <path> <app>...` starts capture, for example `Hotline Capture "/Users/me/Library/Application Support/Hotline/capture.sock" curl firefox`. `<path>` is Hotline's socket file for captured connections (`listen.capture`; a socket file is a connection point in the file system that only programs on this Mac can open). Each app is a piece of a program path or a process number; a leading `!` skips it. When the first entry is a skip rule, everything else is captured. The helper adds a skip rule for its caller, Hotline, so Hotline's own calls are never captured.
- `Hotline Capture --stop` switches capture off. The extension stays installed.

The helper stores the path and the app list in the macOS proxy setting, where the extension reads them when it starts. A new list is a new start: the helper switches capture off and on again, which needs no new approval.

The path must start with `/`, be at most 103 bytes (the longest path macOS keeps for a socket file) and hold no control character. The helper and the extension refuse anything else. The extension never hands over connections to loopback addresses, so a captured app's calls to services on this Mac are not captured. Its own connections to Hotline go over the socket file, which macOS never hands over.

## One captured connection

For each new TCP connection of a listed app, the extension connects to the socket file and sends:

```
CONNECT 93.184.215.14:443 HTTP/1.1
Host: 93.184.215.14:443
User-Agent: HotlineCapture/0.1.1
Hotline-Capture: 2
Hotline-Capture-Pid: 4242
Hotline-Capture-Program: /usr/bin/curl
```

- The target is where the app really called, as macOS reports it (usually an address). IPv6 is written in brackets.
- `User-Agent` names this app and its release version (`CFBundleShortVersionString`), so Hotline can tell which build captured a call. It is not the captured app's own user agent. The version holds only letters, digits, dots and dashes, at most 32 bytes.
- `Hotline-Capture` says the connection was captured; its value is the version.
- `Hotline-Capture-Pid` is the process number of the program.
- `Hotline-Capture-Program` is the program path, as UTF-8. It is left out when unknown, longer than 4096 bytes, or holding a control character.

Hotline answers like any HTTP proxy. A `2xx` status line and headers, ended by an empty line, open the tunnel: after it, both sides send the raw bytes of the app's connection, and either side closing ends it. Any other status, a reply that is not HTTP/1.0 or HTTP/1.1, or a reply over 8 KiB closes the app's connection.

Hotline believes the capture headers only on its socket file, and only when macOS says the program on the other end runs as root, as the extension does. Any other user gets `403`, and a request other than CONNECT gets `405`. On Hotline's proxy port the capture headers are ignored. Hotline refuses version 1 with `400`, as any version it does not know.

## Checking that Hotline is there

macOS wants the answer "capture or not" at once, when a connection starts. So the extension checks Hotline in the background: every 2 seconds it opens a connection to the socket file and closes it, sending nothing. While the last check failed, it captures nothing and every app goes out as usual. When it starts, the extension makes the same check and refuses to start if it fails.
