#!/usr/bin/env python3
"""A stand-in for Hotline, to try the extension by hand on a Mac.

It listens like Hotline's listen.intercept port does, for the extension's
messages only (docs/protocol.md): it answers the control connection with the
app list, and prints each captured connection (where the app really called
and which program it was), then closes it. It needs only Python 3.9 or newer,
which macOS brings with its developer tools. No libraries.

    python3 scripts/try-capture.py --apps curl            # 127.0.0.1:8444
    python3 scripts/try-capture.py --apps curl firefox --listen 127.0.0.1:9000
    python3 scripts/try-capture.py --apps curl --listen sock:///tmp/capture/capture.sock

The matching helper app argument is the same text as --listen.
"""

import argparse
import json
import os
import socket
import socketserver
import stat
import struct
import sys
import threading

VERSION = 1
MAX_FRAME = 16 * 1024


def read_exactly(sock, size):
    data = b""
    while len(data) < size:
        chunk = sock.recv(size - len(data))
        if not chunk:
            raise ConnectionError("closed")
        data += chunk
    return data


def read_frame(sock):
    """Reads one message: 4 bytes of size, big endian, then a JSON body."""
    (size,) = struct.unpack(">I", read_exactly(sock, 4))
    if size > MAX_FRAME:
        raise ValueError("message of %d bytes is over the limit of %d" % (size, MAX_FRAME))
    return json.loads(read_exactly(sock, size).decode("utf-8"))


def frame(message):
    body = json.dumps(message, separators=(",", ":")).encode("utf-8")
    return struct.pack(">I", len(body)) + body


class Handler(socketserver.BaseRequestHandler):
    entries = []

    def handle(self):
        sock = self.request
        try:
            hello = read_frame(sock)
            if hello.get("version") != VERSION:
                print("refused: version %r, want %d" % (hello.get("version"), VERSION))
                return
            role = hello.get("role")
            if role == "control":
                self.control(sock)
            elif role == "flow":
                self.flow(sock, hello)
            else:
                print("refused: unknown role %r" % (role,))
        except (ConnectionError, ValueError, OSError) as error:
            print("connection ended: %s" % (error,))

    def control(self, sock):
        print("control connection from the extension")
        sock.sendall(frame({"version": VERSION, "entries": self.entries}))
        print("  sent the app list %s" % (self.entries,))
        # Stays open: the extension stops capturing when it closes.
        while sock.recv(4096):
            pass
        print("control connection closed: the extension stops capturing")

    def flow(self, sock, hello):
        print(
            "captured: %s:%s from process %s %s"
            % (hello.get("host"), hello.get("port"), hello.get("pid"), hello.get("processName", "(no path)"))
        )
        sock.settimeout(5)
        try:
            first = sock.recv(1)
        except socket.timeout:
            first = b""
        if first == b"\x16":
            print("  its first byte is 0x16, the start of a TLS handshake")
        elif first:
            print("  its first byte is 0x%02x, which is not TLS" % first[0])
        else:
            print("  no bytes followed the hello")
        # Hotline would answer here. The stand-in just ends the connection.


class TcpServer(socketserver.ThreadingMixIn, socketserver.TCPServer):
    allow_reuse_address = True
    daemon_threads = True


class UnixServer(socketserver.ThreadingMixIn, socketserver.UnixStreamServer):
    daemon_threads = True


def private_folder(path):
    folder = os.path.dirname(path)
    os.makedirs(folder, mode=0o700, exist_ok=True)
    info = os.stat(folder)
    if info.st_uid != os.getuid() or stat.S_IMODE(info.st_mode) != 0o700:
        sys.exit("the folder %s must be owned by you with mode 0700" % folder)


def main():
    parser = argparse.ArgumentParser(description="A stand-in for Hotline, to try the extension by hand.")
    parser.add_argument("--apps", nargs="+", required=True, help="programs to capture, by name or process number, ! to skip")
    parser.add_argument("--listen", default="127.0.0.1:8444", help="127.0.0.1:8444, or sock:// and an absolute path")
    args = parser.parse_args()

    # Like Hotline, always skip this process, so it is never captured.
    Handler.entries = args.apps + ["!%d" % os.getpid()]

    if args.listen.startswith("sock://"):
        path = args.listen[len("sock://"):]
        if not path.startswith("/"):
            sys.exit("after sock:// the path must start with a slash")
        private_folder(path)
        if os.path.exists(path):
            os.unlink(path)
        server = UnixServer(path, Handler)
    else:
        host, _, port = args.listen.rpartition(":")
        host = host.strip("[]")
        if host not in ("127.0.0.1", "::1", "localhost") and not host.startswith("127."):
            sys.exit("the address must be on this Mac only, such as 127.0.0.1:8444")
        server = TcpServer((host, int(port)), Handler)

    print("listening on %s, app list %s" % (args.listen, Handler.entries))
    print("start the helper app with the same address; stop with Ctrl-C")
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        server.server_close()
        if args.listen.startswith("sock://"):
            try:
                os.unlink(args.listen[len("sock://"):])
            except OSError:
                pass


if __name__ == "__main__":
    main()
