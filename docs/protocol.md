# How the extension talks to Hotline (capture version 1)

This is the contract between this app and the Hotline proxy (Go, in `petercipov/hotline`). It is plain HTTP: a CONNECT request with a `User-Agent` and three headers of ours. Change this file together with `Sources/CaptureCore/ConnectRequest.swift`, and raise `ConnectRequest.captureVersion` when a header changes.

## Starting and stopping

Hotline runs the helper app:

- `Hotline Capture <address> <app>...` starts capture, for example `Hotline Capture 127.0.0.1:8080 curl firefox`. `<address>` is Hotline's proxy port (`listen.proxy`), on this Mac. Each app is a piece of a program path or a process number; a leading `!` skips it. When the first entry is a skip rule, everything else is captured. The helper adds a skip rule for its caller, Hotline, so Hotline's own calls are never captured.
- `Hotline Capture --stop` switches capture off. The extension stays installed.

The helper stores the address and the app list in the macOS proxy setting, where the extension reads them when it starts. A new list is a new start: the helper switches capture off and on again, which needs no new approval.

The address must be a loopback address (`127.x.x.x`, `::1` in brackets, or `localhost`). The helper and the extension refuse anything else. The extension never hands over connections to loopback addresses, so its own connections to Hotline are never captured, and a captured app's calls to services on this Mac are not captured either.

## One captured connection

For each new TCP connection of a listed app, the extension connects to the address and sends:

```
CONNECT 93.184.215.14:443 HTTP/1.1
Host: 93.184.215.14:443
User-Agent: HotlineCapture/0.1.1
Hotline-Capture: 1
Hotline-Capture-Pid: 4242
Hotline-Capture-Program: /usr/bin/curl
```

- The target is where the app really called, as macOS reports it (usually an address). IPv6 is written in brackets.
- `User-Agent` names this app and its release version (`CFBundleShortVersionString`), so Hotline can tell which build captured a call. It is not the captured app's own user agent. The version holds only letters, digits, dots and dashes, at most 32 bytes.
- `Hotline-Capture` says the connection was captured; its value is the version.
- `Hotline-Capture-Pid` is the process number of the program.
- `Hotline-Capture-Program` is the program path, as UTF-8. It is left out when unknown, longer than 4096 bytes, or holding a control character.

Hotline answers like any HTTP proxy. A `2xx` status line and headers, ended by an empty line, open the tunnel: after it, both sides send the raw bytes of the app's connection, and either side closing ends it. Any other status, a reply that is not HTTP/1.0 or HTTP/1.1, or a reply over 8 KiB closes the app's connection.

Hotline believes the capture headers only when the CONNECT comes from a loopback address. A CONNECT from anywhere else is treated as an ordinary one.

## Checking that Hotline is there

macOS wants the answer "capture or not" at once, when a connection starts. So the extension checks Hotline in the background: every 2 seconds it opens a TCP connection to the address and closes it, sending nothing. While the last check failed, it captures nothing and every app goes out as usual. When it starts, the extension makes the same check and refuses to start if it fails.
