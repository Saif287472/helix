"""Serve the Helix Admin prototype on http://127.0.0.1:5318 with caching off,
so every reload shows the latest edits. Run: python serve.py"""
import functools
import http.server
import os

PORT = 5318
ROOT = os.path.dirname(os.path.abspath(__file__))


class NoCache(http.server.SimpleHTTPRequestHandler):
    def end_headers(self):
        self.send_header('Cache-Control', 'no-store')
        super().end_headers()

    def log_message(self, *args):
        pass


if __name__ == '__main__':
    handler = functools.partial(NoCache, directory=ROOT)
    with http.server.ThreadingHTTPServer(('127.0.0.1', PORT), handler) as httpd:
        print(f'Helix Admin prototype on http://127.0.0.1:{PORT}')
        httpd.serve_forever()
