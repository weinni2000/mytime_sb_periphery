# mytime_sb_periphery

Side services for the schwarzes-brett Odoo (`mytime_sb`), run separately
from the Doodba stack.

## Valhalla (routing / isochrones)

Used by `bulletin_board_isochrone` for "search by travel time". Covers
Austria and all its neighbouring countries (Germany, Czechia, Slovakia,
Hungary, Slovenia, Italy, Switzerland, Liechtenstein).

Two variants:

- **Server (slim):** `docker-compose.yml` only. `valhalla` runs the plain
  `ghcr.io/valhalla/valhalla` image with `valhalla_service`, serving the
  prebuilt `valhalla/custom_files/valhalla_tiles.tar` read-only. Nothing is
  downloaded or built there.
- **Development (fat):** additionally `docker-compose.override.yml`, which
  compose loads automatically. It adds the build services that download the
  OSM extracts and build the tiles. It is never synced to the server.

Development:

```bash
./valhalla/rebuild.sh                  # first setup and every data update
docker compose up -d valhalla          # start / restart the server
curl http://127.0.0.1:8002/status
sync/sync_to_server.sh                 # copy compose file + built tiles to the server
```

Server (after the sync):

```bash
cd ~/schwarzes-brett/odoo/custom/src/mytime_sb_periphery
docker compose up -d valhalla
curl http://127.0.0.1:8002/status
```

The tiles are built with `valhalla-scripted:latest` and served with
`valhalla:latest`; pull both together (`docker compose --profile build pull`)
so builder and server stay on the same Valhalla version.

`valhalla/rebuild.sh` runs two one-off services (compose profile `build`,
defined in `docker-compose.override.yml`):

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
`docker-compose.override.yml` and run `./valhalla/rebuild.sh`.

Nothing of the data is committed (see `.gitignore`).

Odoo uses the server through the system parameters
`bulletin_board_isochrone.valhalla_url` = `http://host.docker.internal:8002`
and `bulletin_board_isochrone.provider` = `valhalla`. With the neighbouring
countries included, set `bulletin_board_isochrone.border_hint` = `0`.

## Container registry

Private registry for our own images (`registry:2`) with a web UI
(`joxit/docker-registry-ui`). Both listen on localhost only.

```bash
./registry/add-user.sh <user>                 # create/update a user (needs Docker)
docker compose up -d registry registry-ui     # start (restart registry after adding users)

docker login 127.0.0.1:5000
docker tag myimage:latest 127.0.0.1:5000/myimage:latest
docker push 127.0.0.1:5000/myimage:latest
```

- UI: <http://127.0.0.1:5080> (log in with the same user)
- Images are stored in `registry/data/`, users in `registry/auth/htpasswd`;
  neither is committed.
- Deleting a tag (UI or API) only removes the reference. To free disk space:
  `docker compose exec registry registry garbage-collect --delete-untagged /etc/docker/registry/config.yml`
- Docker only accepts plain HTTP for localhost. To use the registry from
  another machine, put it behind a TLS reverse proxy (Traefik/Caddy) and
  change the port binding.
