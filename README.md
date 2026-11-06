# mytime_sb_periphery

Side services for the schwarzes-brett Odoo (`mytime_sb`), run separately
from the Doodba stack.

## CDN cache warming

`sitewarm/` wraps the official [sitewarm CLI](https://github.com/sitewarm/sitewarm).
Install the pinned release (1.0.2, verified against its published SHA-256),
then pass your public sitemap URL:

```bash
./sitewarm/install.sh
./sitewarm/warm.sh --dry-run https://your-domain.example/sitemap.xml
./sitewarm/warm.sh https://your-domain.example/sitemap.xml
```

For repeated runs, copy `sitewarm/sitewarm.env.example` to
`sitewarm/sitewarm.env`, set `SITEMAP_URL`, then run `./sitewarm/warm.sh`.
It works from any directory. For cron, use the absolute script path:

```cron
0 5 * * * /home/weinni2000/schwarzes-brett/odoo/custom/src/mytime_sb_periphery/sitewarm/warm.sh
```

Defaults: two requests per second, two concurrent requests, desktop and mobile
profiles, at most 1,000,000 allowed sitemap URLs, and a one-hour overall timeout.
Nested sitemap indexes are followed and robots.txt is respected. Each URL/profile
gets one warming attempt; set `SITEWARM_MAX_WAIT=30s` to retry MISS/STALE responses
and verify cache hits. Timeout means an incomplete scan, not successful completion.
Overlapping runs are skipped using `flock` (Linux/util-linux).

Timestamped logs and JSON results are saved in `sitewarm/reports/`, including
failed scans and partial results on interruption/timeout. Invalid configuration
does not produce a JSON report. The script preserves the CLI's exit status: 0 is
success, 1 is a failed scan, 2 is invalid configuration, and 130/143 is interruption.
The default fail states include cache MISS and HTTP/network errors. BYPASS/DYNAMIC
pages are reported but do not fail the run: warming cannot make them cacheable.
Review the cache-state report rather than assuming a successful scan cached every
page. Remove old reports periodically if scheduling regular runs.

This requests sitemap pages, not all embedded images, CSS or JavaScript. Cloudflare
must permit page caching for HTML to become a HIT. Warming from one machine does
not populate every Cloudflare data center. Use anonymous public pages; authenticated
pages, carts and personalized responses should keep their normal cache exclusions.

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

docker login docker.weingartmair.eu
docker tag myimage:latest docker.weingartmair.eu/myimage:latest
docker push docker.weingartmair.eu/myimage:latest
```

- UI: <https://docker.weingartmair.eu> (log in with the same user)
- On the server, Traefik (`~/inverseproxy/dynamic.yaml`) terminates TLS:
  `/v2/...` goes to the registry on 127.0.0.1:5000, everything else to the
  UI on 127.0.0.1:5080. Keep both ports bound to 127.0.0.1.
- Images are stored in `registry/data/`, users in `registry/auth/htpasswd`;
  neither is committed.
- Deleting a tag (UI or API) only removes the reference. To free disk space:
  `docker compose exec registry registry garbage-collect --delete-untagged /etc/docker/registry/config.yml`
