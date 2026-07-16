#!/usr/bin/env python3
"""Range-capable loopback server for remote-source playback probes."""
from __future__ import annotations

import argparse
import http.server
import pathlib
import re


class Handler(http.server.SimpleHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def send_head(self):
        path = pathlib.Path(self.translate_path(self.path))
        if not path.is_file():
            return super().send_head()
        size = path.stat().st_size
        match = re.fullmatch(r"bytes=(\d*)-(\d*)", self.headers.get("Range", ""))
        start, end = 0, size - 1
        if match:
            start = int(match.group(1) or 0)
            end = min(int(match.group(2) or end), end)
            if start > end:
                self.send_error(416)
                return None
        handle = path.open("rb")
        self.send_response(206 if match else 200)
        self.send_header("Content-Type", self.guess_type(str(path)))
        self.send_header("Accept-Ranges", "bytes")
        self.send_header("Content-Length", str(end - start + 1))
        if match:
            self.send_header("Content-Range", f"bytes {start}-{end}/{size}")
        self.end_headers()
        handle.seek(start)
        self._remaining = end - start + 1
        return handle

    def copyfile(self, source, outputfile):
        remaining = getattr(self, "_remaining", None)
        while remaining is None or remaining > 0:
            chunk = source.read(64 * 1024 if remaining is None else min(64 * 1024, remaining))
            if not chunk:
                break
            outputfile.write(chunk)
            if remaining is not None:
                remaining -= len(chunk)

    def log_message(self, *_):
        pass


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--directory", type=pathlib.Path, required=True)
    parser.add_argument("--port", type=int, default=8765)
    args = parser.parse_args()
    handler = lambda *a, **kw: Handler(*a, directory=str(args.directory), **kw)
    http.server.ThreadingHTTPServer(("127.0.0.1", args.port), handler).serve_forever()


if __name__ == "__main__":
    main()
