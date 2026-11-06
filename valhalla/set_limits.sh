#!/bin/sh
# Raise the isochrone limits of a valhalla.json (default: the served one).
# The image writes the defaults (4 contours) on every build; the near me
# search of bulletin_board_ai_search asks for up to 10 travel times in one
# request: the time a request takes grows with the longest travel time,
# not with the number of contours.
# The builder writes the config as root: changed in the builder image
# (already there for valhalla-build, never pulled here).
# Usage: valhalla/set_limits.sh [path/to/valhalla.json]
set -eu
cd "$(dirname "$0")/.."
config="${1:-valhalla/custom_files/valhalla.json}"
config_dir="$(cd "$(dirname "$config")" && pwd)"
docker run --rm -i --pull=never \
    -v "$config_dir:/config" \
    --entrypoint python3 \
    ghcr.io/valhalla/valhalla-scripted:latest - "/config/$(basename "$config")" <<'PY'
import json
import sys

path = sys.argv[1]
with open(path) as config_file:
    config = json.load(config_file)
config["service_limits"]["isochrone"]["max_contours"] = 10
with open(path, "w") as config_file:
    json.dump(config, config_file, indent=2)
    config_file.write("\n")
PY
echo "Set the isochrone limits in $config (max_contours 10)."
