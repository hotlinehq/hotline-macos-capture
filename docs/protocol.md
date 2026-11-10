# Socket protocol (version 1)

This is the contract between this app and the Hotline proxy (Go, in `petercipov/hotline`). Hotline listens; the extension connects. Change this file together with `Sources/CaptureCore/Messages.swift` and raise `captureProtocolVersion`.

## The connection

The extension connects over TCP to Hotline's `listen.intercept` port. Hotline passes the address as `host:port` to the helper app as its only argument, and the helper stores it in the proxy setting, so the extension gets it from macOS. The address must be a loopback address (`127.x.x.x`, `::1` in brackets, or `localhost`), so only this Mac can reach it; the helper app and the extension both refuse anything else. Hotline refuses to start when asked to capture on an address that is not loopback, and does not check who connects.

The extension never hands over connections to loopback addresses, so its own connection to Hotline is never captured. This also means a captured app's calls to services on this Mac are not captured.

The same port also takes TLS connections from apps (the intercept ingress). The first byte tells them apart: a TLS handshake starts with 0x16, and the messages below start with the size of the body, so with 0x00. Hotline takes these messages only when it was asked to capture apps; otherwise they are refused like any bytes that are not TLS.

## Framing

Every message is: 4 bytes with the size of the body (big endian), then the body as JSON (UTF-8). A size over 16384 bytes, or a body that is not valid, closes the connection. A message with another `version` than the one both sides know is refused.

## Connections

The extension opens two kinds of connection to the same port. Its first message says which.

### Control (one, kept open)

1. Extension sends `ClientHello` with `role: "control"`.
2. Hotline sends a `SpecUpdate` right away, and again whenever the app list changes.

```json
{"version":1,"entries":["curl","firefox","!1234"]}
```

Entries are program names (matched as a piece of the program path) or process numbers. A leading `!` skips the match. When the first entry is a skip rule, everything else is captured; otherwise only matches are. An empty list captures nothing, which stops capture. Hotline's own processes must always appear as skip rules.

If the control connection closes, the extension stops capturing.

### Flow (one per captured connection)

1. Extension sends `ClientHello` with `role: "flow"`:

```json
{"version":1,"role":"flow","transport":"tcp","host":"api.example.com","port":443,"pid":4242,"processName":"/usr/bin/curl"}
```

`host` is the real destination, as the app asked for it (a name or an address). `processName` is the program path and may be missing.

2. After that single message, both sides send raw bytes of the connection with no more framing. Bytes that arrive in the same read as the hello, after it, belong to the connection.
3. Either side closing ends the connection.

Only `transport: "tcp"` is used for now.
