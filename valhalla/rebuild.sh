#!/bin/sh
# Download Austria and its neighbouring countries, build the Valhalla routing
# tiles and swap them in for the running server. Run from anywhere; takes
# a while (see README.md).
set -eu
cd "$(dirname "$0")/.."

docker compose --profile build run --rm valhalla-data
docker compose --profile build run --rm valhalla-build

if [ ! -f valhalla/build/valhalla_tiles.tar ]; then
    echo "No valhalla_tiles.tar was built, keeping the current tiles." >&2
    exit 1
fi

docker compose stop valhalla
rm -rf valhalla/custom_files.previous
if [ -d valhalla/custom_files ]; then
    mv valhalla/custom_files valhalla/custom_files.previous
fi
mv valhalla/build valhalla/custom_files
docker compose up -d valhalla
echo "Swapped in the new tiles; the previous ones are in valhalla/custom_files.previous."
