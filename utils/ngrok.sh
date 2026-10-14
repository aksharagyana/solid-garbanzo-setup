#!/bin/bash

# ------------------------------------------------------------------------------
# ngrok_install_debian
# Install ngrok via apt (Debian/Ubuntu containers).
# Requires root; sets up the official ngrok apt repository.
# ------------------------------------------------------------------------------
ngrok_install_debian() {
  curl -sSL https://ngrok-agent.s3.amazonaws.com/ngrok.asc \
    | tee /etc/apt/trusted.gpg.d/ngrok.asc >/dev/null \
    && echo "deb https://ngrok-agent.s3.amazonaws.com bookworm main" \
    | tee /etc/apt/sources.list.d/ngrok.list \
    && apt update \
    && apt install -y ngrok
}

# ------------------------------------------------------------------------------
# ngrok_config_authtoken
# Configure ngrok with NGROK_AUTH_TOKEN from the environment.
# ------------------------------------------------------------------------------
ngrok_config_authtoken() {
  if [[ -z "${NGROK_AUTH_TOKEN:-}" ]]; then
    echo "Error: NGROK_AUTH_TOKEN is not set." >&2
    return 1
  fi
  ngrok config add-authtoken "${NGROK_AUTH_TOKEN}"
}

# ------------------------------------------------------------------------------
# ngrok_serve_json_dir
# Start a local JSON REST server for a directory and expose it via ngrok.
#
# Maps URL paths to {dir}/{resource}.json using the first path segment:
#   GET    /users       -> read  users.json  (404 if missing)
#   GET    /users1      -> read  users1.json (404 if missing)
#   POST   /users/1234  -> write users.json  (body = JSON payload)
#   PUT    /users/1234  -> same as POST
#   DELETE /users       -> delete users.json (404 if missing)
#
# Usage:
#   ngrok_serve_json_dir -d /full/path/to/dir [-p port]
#
# Requires: python3, ngrok, NGROK_AUTH_TOKEN (unless already configured).
# Runs until Ctrl+C; cleans up the HTTP server and ngrok on exit.
# ------------------------------------------------------------------------------
ngrok_serve_json_dir() {
  local data_dir=""
  local port=""

  while getopts ":d:p:h" opt; do
    case "${opt}" in
      d) data_dir="${OPTARG}" ;;
      p) port="${OPTARG}" ;;
      h)
        cat <<'EOF'
Usage: ngrok_serve_json_dir -d /full/path/to/dir [-p port]

  -d  Directory containing JSON files (required; must exist)
  -p  Local HTTP port (default: random free port)

URL mapping (first path segment -> {dir}/{name}.json):
  GET    /users       read users.json
  POST   /users/1234  write users.json
  PUT    /users/1234  write users.json
  DELETE /users       delete users.json
EOF
        return 0
        ;;
      \?) echo "Invalid option: -$OPTARG" >&2; return 1 ;;
      :) echo "Option -$OPTARG requires an argument." >&2; return 1 ;;
    esac
  done

  if [[ -z "${data_dir}" ]]; then
    echo "Error: -d /full/path/to/dir is required." >&2
    return 1
  fi

  if [[ ! -d "${data_dir}" ]]; then
    echo "Error: directory does not exist: ${data_dir}" >&2
    return 1
  fi

  data_dir="$(cd "${data_dir}" && pwd)"

  if ! command -v python3 >/dev/null 2>&1; then
    echo "Error: python3 not found in PATH." >&2
    return 1
  fi

  if ! command -v ngrok >/dev/null 2>&1; then
    echo "Error: ngrok not found in PATH." >&2
    return 1
  fi

  if [[ -z "${port}" ]]; then
    port="$(python3 -c 'import socket; s=socket.socket(); s.bind(("",0)); print(s.getsockname()[1]); s.close()')"
  fi

  local server_pid ngrok_pid cleanup_done=0

  cleanup() {
    [[ "${cleanup_done}" -eq 1 ]] && return
    cleanup_done=1
    echo
    echo "Shutting down..."
    [[ -n "${ngrok_pid:-}" ]] && kill "${ngrok_pid}" 2>/dev/null
    [[ -n "${server_pid:-}" ]] && kill "${server_pid}" 2>/dev/null
    wait "${ngrok_pid}" 2>/dev/null
    wait "${server_pid}" 2>/dev/null
  }

  trap cleanup INT TERM EXIT

  python3 - "${data_dir}" "${port}" <<'PY' &
import json
import os
import sys
from http.server import BaseHTTPRequestHandler, HTTPServer
from urllib.parse import urlparse

ROOT_DIR = sys.argv[1]
PORT = int(sys.argv[2])


def json_file_for_path(url_path):
    """Map /users or /users/1234 -> {ROOT_DIR}/users.json"""
    segment = url_path.strip("/").split("/", 1)[0]
    if not segment:
        return None
    return os.path.join(ROOT_DIR, f"{segment}.json")


class JsonDirHandler(BaseHTTPRequestHandler):
    def _respond(self, status, body, content_type="application/json"):
        self.send_response(status)
        self.send_header("Content-Type", content_type)
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def _read_body(self):
        length = int(self.headers.get("Content-Length", 0))
        return self.rfile.read(length) if length else b""

    def do_GET(self):
        path = urlparse(self.path).path
        json_path = json_file_for_path(path)
        if not json_path or not os.path.isfile(json_path):
            self._respond(404, b'{"error":"not found"}')
            return
        with open(json_path, "rb") as fh:
            self._respond(200, fh.read())

    def do_POST(self):
        self._write_json()

    def do_PUT(self):
        self._write_json()

    def _write_json(self):
        path = urlparse(self.path).path
        json_path = json_file_for_path(path)
        if not json_path:
            self._respond(400, b'{"error":"invalid path"}')
            return
        body = self._read_body()
        if body:
            try:
                json.loads(body)
            except json.JSONDecodeError:
                self._respond(400, b'{"error":"body must be valid JSON"}')
                return
        os.makedirs(os.path.dirname(json_path) or ".", exist_ok=True)
        with open(json_path, "wb") as fh:
            fh.write(body)
        self._respond(200, b'{"status":"ok"}')

    def do_DELETE(self):
        path = urlparse(self.path).path
        json_path = json_file_for_path(path)
        if not json_path or not os.path.isfile(json_path):
            self._respond(404, b'{"error":"not found"}')
            return
        os.remove(json_path)
        self._respond(200, b'{"status":"deleted"}')

    def log_message(self, fmt, *args):
        print(f"[json-serve:{PORT}] {self.address_string()} - {fmt % args}", flush=True)


if __name__ == "__main__":
    server = HTTPServer(("127.0.0.1", PORT), JsonDirHandler)
    print(f"[json-serve] serving {ROOT_DIR} on http://127.0.0.1:{PORT}", flush=True)
    server.serve_forever()
PY
  server_pid=$!

  sleep 0.5
  if ! kill -0 "${server_pid}" 2>/dev/null; then
    echo "Error: JSON HTTP server failed to start." >&2
    return 1
  fi

  ngrok http "0.0.0.0:${port}" --log=stdout >/dev/null 2>&1 &
  ngrok_pid=$!

  local public_url=""
  local attempt
  for attempt in $(seq 1 30); do
    public_url="$(curl -sf http://127.0.0.1:4040/api/tunnels 2>/dev/null \
      | python3 -c "
import json, sys
data = json.load(sys.stdin)
for t in data.get('tunnels', []):
    url = t.get('public_url', '')
    if url.startswith('https://'):
        print(url)
        break
" 2>/dev/null || true)"
    [[ -n "${public_url}" ]] && break
    sleep 0.5
  done

  if [[ -z "${public_url}" ]]; then
    echo "Error: could not obtain ngrok public URL (is NGROK_AUTH_TOKEN configured?)." >&2
    return 1
  fi

  echo "Local server:  http://127.0.0.1:${port}"
  echo "Ngrok endpoint: ${public_url}"
  echo "Data directory: ${data_dir}"
  echo
  echo "Examples (resource = first URL segment -> {name}.json):"
  echo "  curl ${public_url}/users"
  echo "  curl -X POST ${public_url}/users/1234 -H 'Content-Type: application/json' -d '{\"id\":1234}'"
  echo "  curl -X DELETE ${public_url}/users"
  echo
  echo "Press Ctrl+C to stop."

  wait "${server_pid}"
}
