from __future__ import annotations

from functools import partial
from http.server import ThreadingHTTPServer
from pathlib import Path
import sys
import tempfile
import threading
import unittest
import urllib.request


ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tools" / "playback"))
from serve_fixtures import Handler  # noqa: E402


class FixtureServerTests(unittest.TestCase):
    def test_explicit_byte_range_returns_only_requested_bytes(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            payload = bytes(range(64))
            (Path(directory) / "fixture.bin").write_bytes(payload)
            server = ThreadingHTTPServer(
                ("127.0.0.1", 0),
                partial(Handler, directory=directory),
            )
            thread = threading.Thread(target=server.serve_forever, daemon=True)
            thread.start()
            try:
                request = urllib.request.Request(
                    f"http://127.0.0.1:{server.server_port}/fixture.bin",
                    headers={"Range": "bytes=10-11"},
                )
                with urllib.request.urlopen(request) as response:
                    self.assertEqual(response.status, 206)
                    self.assertEqual(response.headers["Content-Length"], "2")
                    self.assertEqual(response.headers["Content-Range"], "bytes 10-11/64")
                    self.assertEqual(response.read(), payload[10:12])
            finally:
                server.shutdown()
                server.server_close()
                thread.join(timeout=2)


if __name__ == "__main__":
    unittest.main()
