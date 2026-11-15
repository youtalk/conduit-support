# Conduit router image

For maintainers. The Zenoh router that `pair.sh` starts on a computer without ROS 2 (a Mac, a
Linux PC without ROS 2, or `--container`): `rmw_zenohd` from `rmw_zenoh_cpp`, plus the ROS 2 CLI
and the message packages Conduit's topics need (`tf2_msgs`, `point_cloud_interfaces` and
`audio_common_msgs`, built from source because it has no binary package). The iPhone and the
user's own ROS 2 containers connect to it.

One `Dockerfile` builds the image for each distribution the router is offered on: Jazzy and
Lyrical. A Rolling PC uses the Lyrical image. Humble (a different Zenoh wire format) and Kilted are
not offered.

## How pair.sh runs it

```bash
docker run -d --name conduit-router --restart unless-stopped \
  -p <router port>:7447 -p <check-in port>:7449 ghcr.io/youtalk/conduit-router:lyrical-<version>
```

- `pair.sh` waits for `Started Zenoh router` in the log, then runs the QR code and the check-in
  listener with the container's `python3` (`docker exec -i conduit-router python3`), and checks
  for Conduit's node and `/tf_static` with `docker exec conduit-router with-ros ros2 ...`.
  `with-ros` sources ROS 2, because `docker exec` skips the entrypoint.
- The Robots demo joins the router's graph with `--network container:conduit-router` and the
  demo image's `join` mode (`docker/demo/README.md`).
- `--restart unless-stopped` brings the router back with Docker, on the same ports, so Conduit
  reconnects without pairing again. `docker stop conduit-router` stops it for good.

## Build and publish

```bash
docker build -f docker/router/Dockerfile --build-arg ROS_DISTRO=lyrical -t conduit-router:lyrical-dev .
CONDUIT_ROUTER_IMAGE=conduit-router:lyrical-dev bash pair/pair.sh --container
```

`.github/workflows/router-image.yml` builds the Lyrical image on a pull request (no push). A tag
`router-v<version>` pushes `ghcr.io/youtalk/conduit-router:<distro>-<version>` and
`:<distro>` for linux/amd64 and linux/arm64, and never overwrites a published
`<distro>-<version>`. `pair.sh` pins the version in `PAIR_ROUTER_VERSION`: tag the version it
names before `pair.sh` reaches the site.
