# Socket protocol (version 1)

This is the contract between this app and the Hotline proxy (Go, in `petercipov/hotline`). Hotline listens; the extension connects. Change this file together with `Sources/CaptureCore/Messages.swift` and raise `captureProtocolVersion`.

## The socket

Hotline creates one Unix socket (a local file-like channel) in a private folder: made by Hotline with a random name, mode 0700, owned by the user. The path is passed to the helper app as its only argument and stored in the proxy setting, so the extension gets it from macOS.

Hotline must check who connects (peer user): only the same user or root. Anything else is refused.

## Framing

Every message is: 4 bytes with the size of the body (big endian), then the body as JSON (UTF-8). A size over 16384 bytes, or a body that is not valid, closes the connection. A message with another `version` than the one both sides know is refused.

## Connections

The extension opens two kinds of connection to the same socket. Its first message says which.

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
