#!/usr/bin/env python3
"""Minimal OpenAI-compatible chat-completions mock for tests/test_ai_enrichment.gd."""
import json
import sys
from http.server import BaseHTTPRequestHandler, HTTPServer


class Handler(BaseHTTPRequestHandler):
    def do_POST(self):
        length = int(self.headers.get("Content-Length", 0))
        req = json.loads(self.rfile.read(length) or b"{}")
        prompt = req.get("messages", [{}])[-1].get("content", "")
        if "flavor" in prompt:
            content = {"flavor": "It remembers every road it has ever travelled."}
        else:
            content = {"bio": "Mock skies are kinder than they look.", "backstory": "Raised by a travelling orchestra. Joined the company for the view."}
        body = json.dumps({"choices": [{"message": {"role": "assistant", "content": json.dumps(content)}}]}).encode()
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, *args):
        pass


if __name__ == "__main__":
    HTTPServer(("127.0.0.1", int(sys.argv[1])), Handler).serve_forever()
