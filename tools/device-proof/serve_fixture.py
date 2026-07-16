#!/usr/bin/env python3
from http.server import ThreadingHTTPServer, SimpleHTTPRequestHandler
from functools import partial
import argparse, json, socket
from pathlib import Path

p = argparse.ArgumentParser()
p.add_argument("--root", required=True); p.add_argument("--state", required=True)
args = p.parse_args()

class Handler(SimpleHTTPRequestHandler):
    def log_message(self, fmt, *values): pass

server = ThreadingHTTPServer(("0.0.0.0", 0), partial(Handler, directory=args.root))
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
