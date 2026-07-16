#!/usr/bin/env python3
from http.server import ThreadingHTTPServer
from functools import partial
import argparse
import json
import socket
from pathlib import Path
import sys

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "playback"))
from serve_fixtures import Handler  # noqa: E402

p = argparse.ArgumentParser()
p.add_argument("--root", required=True); p.add_argument("--state", required=True)
p.add_argument("--bytes-per-second", type=int, default=0)
args = p.parse_args()

server = ThreadingHTTPServer(("0.0.0.0", 0), partial(Handler, directory=args.root))
server.bytes_per_second = args.bytes_per_second
s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
try:
    s.connect(("192.0.2.1", 9)); address = s.getsockname()[0]
finally: s.close()
Path(args.state).write_text(json.dumps({"url": f"http://{address}:{server.server_port}/tone-a.m4a"}), encoding="utf-8")
try:
    server.serve_forever()
except KeyboardInterrupt:
    pass
finally:
    server.server_close()
