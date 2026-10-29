#!/bin/sh
# Copy the Valhalla routing server and the map tileserver to the remote host,
# into the same paths as here. Only the files the running servers need are
# sent: the OSM downloads, the merged region.osm.pbf and the unpacked tile
# directory are skipped (Valhalla reads valhalla_tiles.tar).
#
# Usage: sync/sync_to_server.sh [extra rsync options, e.g. --dry-run]
set -eu

REMOTE="weinni2000@62.169.26.81"
SRC="/home/weinni2000/schwarzes-brett/odoo/custom/src"

ssh "$REMOTE" mkdir -p "$SRC"

# "/./" marks where the path recreated on the remote side starts.
rsync -avhR --partial --info=progress2 "$@" \
    "$SRC/./mytime_sb_periphery/docker-compose.yml" \
    "$SRC/./mytime_sb_periphery/README.md" \
    "$SRC/./mytime_sb_periphery/valhalla/rebuild.sh" \
    "$SRC/./mytime_sb_periphery/valhalla/custom_files/valhalla.json" \
    "$SRC/./mytime_sb_periphery/valhalla/custom_files/valhalla_tiles.tar" \
    "$SRC/./mytime_sb_periphery/valhalla/custom_files/admins.sqlite" \
    "$SRC/./mytime_sb_periphery/valhalla/custom_files/timezones.sqlite" \
    "$SRC/./mytime_sb_periphery/valhalla/custom_files/default_speeds.json" \
    "$SRC/./mytime_sb_periphery/valhalla/custom_files/file_hashes.txt" \
    "$SRC/./tileserver/docker-compose.yml" \
    "$SRC/./tileserver/data" \
    "$REMOTE:$SRC/"
