#!/usr/bin/env python3
"""A stand-in for Hotline, to try the extension by hand on a Mac.

It listens on a socket file like Hotline's listen.capture does, for the
extension's CONNECT requests only (docs/protocol.md): it prints each captured
connection (where the app really called, which program it was, and the user
macOS says opened the socket file, 0 for the extension, which runs as root),
answers 200, reads the
app's first byte, then closes it. Connections that send nothing are the
extension's checks that Hotline is there, and are not printed. It needs only
Python 3.9 or newer, which macOS brings with its developer tools. No libraries.

    python3 scripts/try-capture.py                        # /tmp/hotline-capture.sock
    python3 scripts/try-capture.py --listen /tmp/other.sock

Then start capture with the same path and the apps to capture:

    "/Applications/Hotline Capture.app/Contents/MacOS/Hotline Capture" /tmp/hotline-capture.sock curl
"""

import argparse
import os
import socket
import socketserver
import struct
import sys

MAX_REPLY = 8 * 1024
VERSION = "2"
# macOS: getsockopt(SOL_LOCAL, LOCAL_PEERCRED) gives the user of the
# program on the other end of a socket file.
SOL_LOCAL = 0
LOCAL_PEERCRED = 1


def peer_user(sock):
    """The user of the program on the other end, or None when not known."""
    try:
        cred = sock.getsockopt(SOL_LOCAL, LOCAL_PEERCRED, 64)
        _version, uid = struct.unpack_from("II", cred)
        return uid
    except OSError:
        return None


class Handler(socketserver.BaseRequestHandler):
    def handle(self):
        sock = self.request
        sock.settimeout(5)
        head = b""
        try:
            while b"\r\n\r\n" not in head:
                chunk = sock.recv(1024)
                if not chunk:
                    # The extension's check that Hotline is there: nothing to print.
                    return
                head += chunk
                if len(head) > MAX_REPLY:
                    print("refused: request over %d bytes" % MAX_REPLY)
                    return
        except (socket.timeout, OSError):
            return
        head, _, rest = head.partition(b"\r\n\r\n")
        lines = head.decode("utf-8", "replace").split("\r\n")
        method, _, target = lines[0].partition(" ")
        target = target.rsplit(" ", 1)[0]
        headers = {}
        for line in lines[1:]:
            name, _, value = line.partition(":")
            headers[name.strip().lower()] = value.strip()
        if method != "CONNECT":
            print("refused: %s is not a CONNECT" % lines[0])
            sock.sendall(b"HTTP/1.1 405 Method Not Allowed\r\n\r\n")
            return
        if headers.get("hotline-capture") != VERSION:
            print("refused: Hotline-Capture is %r, want %s" % (headers.get("hotline-capture"), VERSION))
            sock.sendall(b"HTTP/1.1 400 Bad Request\r\n\r\n")
            return
        user = peer_user(sock)
        print(
            "captured: %s from process %s %s (user %s, sent by %s)"
            % (
                target,
                headers.get("hotline-capture-pid"),
                headers.get("hotline-capture-program", "(no path)"),
                user,
                headers.get("user-agent", "no User-Agent"),
            )
        )
        sock.sendall(b"HTTP/1.1 200 Connection established\r\n\r\n")
        first = rest[:1]
        if not first:
            try:
                first = sock.recv(1)
            except socket.timeout:
                first = b""
        if first == b"\x16":
            print("  its first byte is 0x16, the start of a TLS handshake")
        elif first:
            print("  its first byte is 0x%02x, which is not TLS" % first[0])
        else:
            print("  no bytes followed the CONNECT")
        # Hotline would pose as the vendor here. The stand-in just ends the connection.


class Server(socketserver.ThreadingMixIn, socketserver.UnixStreamServer):
    daemon_threads = True


def main():
    parser = argparse.ArgumentParser(description="A stand-in for Hotline, to try the extension by hand.")
    parser.add_argument("--listen", default="/tmp/hotline-capture.sock", help="the socket file, such as /tmp/hotline-capture.sock")
    args = parser.parse_args()

    if not args.listen.startswith("/") or len(args.listen.encode()) > 103:
        sys.exit("the path must start with / and be at most 103 bytes, such as /tmp/hotline-capture.sock")
    # A socket file left by an earlier run would stop the listen.
    if os.path.exists(args.listen):
        os.remove(args.listen)
    server = Server(args.listen, Handler)
    os.chmod(args.listen, 0o600)

    print("listening on %s; stop with Ctrl-C" % args.listen)
    print('start capture with: "/Applications/Hotline Capture.app/Contents/MacOS/Hotline Capture" %s curl' % args.listen)
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        server.server_close()
        os.remove(args.listen)


if __name__ == "__main__":
    main()
