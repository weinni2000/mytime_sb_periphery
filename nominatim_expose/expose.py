#!/usr/bin/env python3
"""Expose the local n7m Nominatim through ngrok and point prod Odoo at it.

Reads .env next to this file (not in git):

    ngrok_api_token=<ngrok authtoken>
    sb_admin_api_key=<Odoo API key of the admin user>
    sb_url=https://schwarzes-brett.info
    sb_ip=62.169.26.81

Starts `ngrok http <port>`, waits for the public URL and writes
`<public URL>/api/v4/` to the `nominatim.url` system parameter of the prod
database. Odoo is reached through `sb_ip` (the origin server), because the
domain is behind Cloudflare. ngrok keeps running until Ctrl-C.
"""

import argparse
import http.client
import json
import logging
import os
import signal
import socket
import ssl
import subprocess
import sys
import time
import urllib.parse
import urllib.request
from pathlib import Path

_logger = logging.getLogger("nominatim_expose")

HERE = Path(__file__).resolve().parent
NGROK_API = "http://localhost:4040/api/tunnels"
PARAM_KEY = "nominatim.url"


def load_env(path):
    if not path.is_file():
        sys.exit(f"missing {path}")
    env = {}
    for line in path.read_text().splitlines():
        line = line.strip()
        if line and not line.startswith("#") and "=" in line:
            key, _separator, value = line.partition("=")
            env[key.strip()] = value.strip()
    missing = [
        key
        for key in ("ngrok_api_token", "sb_admin_api_key", "sb_url", "sb_ip")
        if not env.get(key)
    ]
    if missing:
        sys.exit(f"{path} lacks: {', '.join(missing)}")
    return env


def check_local(port):
    try:
        with urllib.request.urlopen(f"http://localhost:{port}/", timeout=5):
            pass
    except OSError as exc:
        sys.exit(
            f"nothing answers on localhost:{port} ({exc}); "
            "try: docker restart n7m-web-1"
        )


def wait_for_public_url(process, timeout=30):
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        if process.poll() is not None:
            sys.exit(f"ngrok exited with code {process.returncode}")
        try:
            with urllib.request.urlopen(NGROK_API, timeout=2) as response:
                tunnels = json.load(response)["tunnels"]
        except (OSError, ValueError, KeyError):
            tunnels = []
        for tunnel in tunnels:
            if tunnel.get("public_url", "").startswith("https://"):
                return tunnel["public_url"]
        time.sleep(1)
    process.terminate()
    sys.exit(f"ngrok gave no public URL within {timeout}s")


class OdooClient:
    """JSON-RPC client that connects to the origin IP with verified TLS."""

    def __init__(self, env, database, login):
        self.host = urllib.parse.urlparse(env["sb_url"]).hostname
        self.ip = env["sb_ip"]
        self.key = env["sb_admin_api_key"]
        self.database = database
        self.context = ssl.create_default_context()
        self.uid = self.call("common", "authenticate", database, login, self.key, {})
        if not self.uid:
            sys.exit(f"API key rejected for {login} on {database}")

    def call(self, service, method, *args):
        payload = {
            "jsonrpc": "2.0",
            "method": "call",
            "params": {"service": service, "method": method, "args": list(args)},
        }
        connection = http.client.HTTPSConnection(self.host, timeout=30)
        raw_socket = socket.create_connection((self.ip, 443), timeout=30)
        connection.sock = self.context.wrap_socket(
            raw_socket, server_hostname=self.host
        )
        try:
            connection.request(
                "POST",
                "/jsonrpc",
                json.dumps(payload),
                {"Content-Type": "application/json"},
            )
            response = connection.getresponse()
            result = json.loads(response.read())
        finally:
            connection.close()
        if "error" in result:
            error = result["error"]
            message = error.get("data", {}).get("message") or error.get("message")
            sys.exit(f"Odoo error: {message}")
        return result["result"]

    def execute(self, model, method, args, kwargs=None):
        return self.call(
            "object",
            "execute_kw",
            self.database,
            self.uid,
            self.key,
            model,
            method,
            args,
            kwargs or {},
        )

    def set_param(self, key, value):
        domain = [["key", "=", key]]
        records = self.execute(
            "ir.config_parameter", "search_read", [domain], {"fields": ["value"]}
        )
        if records and records[0]["value"] == value:
            _logger.info("%s already %s", key, value)
            return
        if records:
            _logger.info("%s: %s -> %s", key, records[0]["value"], value)
            self.execute(
                "ir.config_parameter",
                "write",
                [[records[0]["id"]], {"value": value}],
            )
        else:
            _logger.info("%s: (unset) -> %s", key, value)
            self.execute(
                "ir.config_parameter", "create", [{"key": key, "value": value}]
            )


def parse_args():
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--port", type=int, default=8080)
    parser.add_argument("--database", default="schwarzes-brett")
    parser.add_argument("--login", default="admin")
    parser.add_argument(
        "--no-update", action="store_true", help=f"do not touch {PARAM_KEY}"
    )
    parser.add_argument("ngrok_args", nargs="*", help="extra ngrok http args, after --")
    return parser.parse_args()


def main():
    logging.basicConfig(level=logging.INFO, format="%(message)s")
    args = parse_args()
    env = load_env(HERE / ".env")
    check_local(args.port)

    process = subprocess.Popen(
        ["ngrok", "http", str(args.port), "--log=false", *args.ngrok_args],
        env={**os.environ, "NGROK_AUTHTOKEN": env["ngrok_api_token"]},
        stdout=subprocess.DEVNULL,
    )
    signal.signal(signal.SIGTERM, lambda _signum, _frame: process.terminate())
    try:
        public_url = wait_for_public_url(process)
        nominatim_url = f"{public_url}/api/v4/"
        _logger.info("Nominatim is public at %s", nominatim_url)
        if not args.no_update:
            client = OdooClient(env, args.database, args.login)
            client.set_param(PARAM_KEY, nominatim_url)
        _logger.info("ngrok running, Ctrl-C to stop")
        process.wait()
    except KeyboardInterrupt:
        _logger.info("stopping ngrok")
    finally:
        if process.poll() is None:
            process.terminate()
            process.wait(timeout=10)
    return process.returncode or 0


if __name__ == "__main__":
    sys.exit(main())
