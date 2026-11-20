#!/usr/bin/env bash
# Expose the local n7m Nominatim (n7m-web-1 on :8080) through ngrok.
# The ngrok token is read from .env next to this script (not in git).
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
port="${NOMINATIM_PORT:-8080}"

if [ ! -f "$here/.env" ]; then
    echo "missing $here/.env with ngrok_api_token=<token>" >&2
    exit 2
fi
token="$(sed -n 's/^ngrok_api_token=//p' "$here/.env" | tr -d '[:space:]')"
if [ -z "$token" ]; then
    echo "ngrok_api_token is empty in $here/.env" >&2
    exit 2
fi

if ! curl -s -o /dev/null --max-time 5 "http://localhost:$port/"; then
    echo "nothing answers on localhost:$port; try: docker restart n7m-web-1" >&2
    exit 1
fi

NGROK_AUTHTOKEN="$token" exec ngrok http "$port" --log=stdout --log-format=logfmt \
    "$@"
