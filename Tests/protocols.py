# SPDX-License-Identifier: GPL-3.0-only
# Copyright (C) 2026 1anzii

"""Exercise production Swift adapters against local, deterministic protocol peers."""
import base64
import http.server
import json
import os
import socket
import subprocess
import sys
import tempfile
import threading
import urllib.parse

binary = sys.argv[1]

def serve_ipc(listener):
    peer, _ = listener.accept()
    rate = 1
    with peer, peer.makefile('rb') as stream:
        for line in stream:
            message = json.loads(line)
            command = message['command']
            value = None
            if command == ['get_property', 'idle-active']:
                value = False
            elif command == ['get_property', 'speed']:
                value = rate
            elif command[:2] == ['set_property', 'speed']:
                rate = command[2]
            else:
                raise AssertionError(command)
            reply = json.dumps({'request_id': message['request_id'], 'error': 'success', 'data': value}).encode() + b'\n'
            peer.sendall(b'{"event":"property-change"}\n')
            peer.sendall(reply[:8])
            peer.sendall(reply[8:])

class VLC(http.server.BaseHTTPRequestHandler):
    rate = 1
    def log_message(self, *args):
        pass
    def do_GET(self):
        expected = 'Basic ' + base64.b64encode(b':slowfast-test').decode()
        if self.headers.get('Authorization') != expected:
            self.send_response(401)
            self.end_headers()
            return
        query = urllib.parse.parse_qs(urllib.parse.urlsplit(self.path).query)
        assert self.path.startswith('/requests/status.json')
        if query:
            assert query['command'] == ['rate']
            VLC.rate = float(query['val'][0])
        body = json.dumps({'state': 'paused', 'rate': VLC.rate}).encode()
        self.send_response(200)
        self.send_header('Content-Type', 'application/json')
        self.send_header('Content-Length', str(len(body)))
        self.end_headers()
        self.wfile.write(body)

with tempfile.TemporaryDirectory(prefix='sf-', dir='/tmp') as folder:
    path = os.path.join(folder, 'iina.sock')
    with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as listener:
        listener.bind(path)
        listener.listen(1)
        thread = threading.Thread(target=serve_ipc, args=(listener,), daemon=True)
        thread.start()
        subprocess.run([binary, 'ipc', path], check=True, timeout=15)
        thread.join(timeout=3)
    subprocess.run([binary, 'ipc-refused', os.path.join(folder, 'missing')], check=True, timeout=10)
with http.server.ThreadingHTTPServer(('127.0.0.1', 0), VLC) as server:
    thread = threading.Thread(target=server.serve_forever, daemon=True)
    thread.start()
    subprocess.run([binary, 'http', str(server.server_port)], check=True, timeout=15)
    assert VLC.rate == 0.75
    server.shutdown()
