# mytime_sb_periphery

Side services for the schwarzes-brett Odoo (`mytime_sb`), run separately
from the Doodba stack.

## Valhalla (routing / isochrones)

Used by `bulletin_board_isochrone` for "search by travel time". Covers
Austria and all its neighbouring countries (Germany, Czechia, Slovakia,
Hungary, Slovenia, Italy, Switzerland, Liechtenstein).

```bash
./valhalla/rebuild.sh                  # first setup and every data update
docker compose up -d valhalla          # start / restart the server
curl http://127.0.0.1:8002/status
```

`valhalla/rebuild.sh` runs two one-off services (compose profile `build`):

1. `valhalla-data` downloads the country extracts from Geofabrik into
   `valhalla/downloads/` (only newer ones on later runs) and merges them with
   `osmium merge` into `valhalla/build/region.osm.pbf`. The country extracts
   overlap at the borders; merging removes the duplicated roads.
2. `valhalla-build` builds the routing tiles into `valhalla/build/`.

Then it stops the server, moves the served tiles to
`valhalla/custom_files.previous/`, moves the new build to
`valhalla/custom_files/` and starts the server again. The running server
keeps answering with the old tiles during the build. Delete
`valhalla/custom_files.previous/` once the new tiles work.

To change the countries, edit `region_urls` of `valhalla-data` in
`docker-compose.yml` and run `./valhalla/rebuild.sh`.

Nothing of the data is committed (see `.gitignore`).

Odoo uses the server through the system parameters
`bulletin_board_isochrone.valhalla_url` = `http://host.docker.internal:8002`
and `bulletin_board_isochrone.provider` = `valhalla`. With the neighbouring
countries included, set `bulletin_board_isochrone.border_hint` = `0`.
