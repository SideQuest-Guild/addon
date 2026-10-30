import json
import threading
from http.server import BaseHTTPRequestHandler, HTTPServer

import pytest

from sidequest_sync.upload import UploadError, upload_payload


class _FakeImportsHandler(BaseHTTPRequestHandler):
    # populated per-test via server.behavior
    def log_message(self, *args):  # silence test output
        pass

    def do_POST(self):
        behavior = self.server.behavior
        length = int(self.headers.get("Content-Length", 0))
        raw_body = self.rfile.read(length)
        self.server.last_request = {
            "path": self.path,
            "headers": dict(self.headers.items()),
            "body": json.loads(raw_body) if raw_body else None,
        }

        status, payload = behavior(self.server.last_request)
        body = json.dumps(payload).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)


@pytest.fixture
def fake_server():
    server = HTTPServer(("127.0.0.1", 0), _FakeImportsHandler)
    server.behavior = lambda req: (200, {})
    server.last_request = None
    thread = threading.Thread(target=server.serve_forever, daemon=True)
    thread.start()
    yield server
    server.shutdown()
    thread.join(timeout=5)


def _url(server: HTTPServer) -> str:
    return f"http://127.0.0.1:{server.server_address[1]}"


def test_upload_success_sends_payload_and_bearer_token(fake_server):
    def behavior(req):
        assert req["path"] == "/api/epgp/imports"
        assert req["headers"]["Authorization"] == "Bearer sqs_test_token"
        assert req["body"] == {"payload": "SQX1:AAAA=="}
        return 200, {
            "recorder": "Officername-Whitemane",
            "sessions": {"new": 1, "updated": 0},
            "encounters": {"new": 2, "updated": 0},
            "loot": {"new": 1, "updated": 0, "voided": 0},
            "awards": {"new": 5, "updated": 0, "voided": 0},
            "unlinked_characters": ["Mystery-Realm"],
            "attendance": {"event_id": "evt-1", "marked": 4},
        }

    fake_server.behavior = behavior
    result = upload_payload(_url(fake_server), "sqs_test_token", "SQX1:AAAA==")

    assert result.recorder == "Officername-Whitemane"
    assert result.sessions == {"new": 1, "updated": 0}
    assert result.unlinked_characters == ["Mystery-Realm"]
    assert result.attendance == {"event_id": "evt-1", "marked": 4}


def test_upload_400_raises_readable_error(fake_server):
    fake_server.behavior = lambda req: (400, {"detail": "malformed SQX1 payload"})
    with pytest.raises(UploadError, match="malformed SQX1 payload"):
        upload_payload(_url(fake_server), "sqs_test_token", "SQX1:bad")


def test_upload_401_raises_readable_error(fake_server):
    fake_server.behavior = lambda req: (401, {"detail": "invalid token"})
    with pytest.raises(UploadError, match="login"):
        upload_payload(_url(fake_server), "sqs_bad_token", "SQX1:AAAA==")


def test_upload_403_raises_readable_error(fake_server):
    fake_server.behavior = lambda req: (403, {"detail": "no longer an officer"})
    with pytest.raises(UploadError, match="no longer an officer"):
        upload_payload(_url(fake_server), "sqs_test_token", "SQX1:AAAA==")


def test_upload_network_error_raises_readable_error():
    with pytest.raises(UploadError, match="Could not reach"):
        upload_payload("http://127.0.0.1:1", "sqs_test_token", "SQX1:AAAA==", timeout=1)
