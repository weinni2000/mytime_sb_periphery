# mytime_sb_periphery

Side services for the schwarzes-brett Odoo (`mytime_sb`), run separately
from the Doodba stack.

## Valhalla (routing / isochrones)

Used by `bulletin_board_isochrone` for "search by travel time".

```bash
docker compose up -d valhalla
docker compose logs -f valhalla        # first start: download + tile build
curl http://127.0.0.1:8002/status
```

The first start downloads the Austria extract from Geofabrik and builds the
routing tiles into `valhalla/custom_files/` (not committed). Later starts
reuse the tiles.

- Update the map data: delete `valhalla/custom_files/austria-latest.osm.pbf`
  (or set `force_rebuild: "True"`) and restart.
- More countries: add their `.osm.pbf` URLs to `tile_urls`, separated by
  spaces, and rebuild.

Odoo uses it through the system parameter
`bulletin_board_isochrone.valhalla_url` = `http://host.docker.internal:8002`
(and `bulletin_board_isochrone.provider` = `valhalla`).
