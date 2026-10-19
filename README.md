# Tor [![code style: prettier](https://img.shields.io/badge/code_style-prettier-ff69b4.svg)](https://github.com/prettier/prettier) [![Contributor Covenant](https://img.shields.io/badge/Contributor%20Covenant-2.1-4baaaa.svg)](CODE_OF_CONDUCT.md) [![semantic-release](https://img.shields.io/badge/%20%20%F0%9F%93%A6%F0%9F%9A%80-semantic--release-e10079.svg)](https://github.com/semantic-release/semantic-release) [![Conventional Commits](https://img.shields.io/badge/Conventional%20Commits-1.0.0-yellow.svg)](https://conventionalcommits.org)

A simple docker container to access the [Tor](https://www.torproject.org/) network.

## Usage

Set the image once, the commands below use it:

```sh
TOR_IMAGE=ghcr.io/vansergen/tor:2
```

### SOCKS proxy example

1. Start the service

```sh
docker run --name tor --publish 9050:9050 --volume tor:/var/lib/tor --detach "$TOR_IMAGE"
```

2. Test the connection

```sh
curl --socks5-hostname localhost:9050 https://api64.ipify.org
```

#### `obfs4` bridges

0. Add bridges to `./bridges.conf`

```
UseBridges 1
Bridge obfs4 <IP>:<PORT> <FOOTPRINT> cert=<CERT> iat-mode=0
Bridge obfs4 <IP>:<PORT> <FOOTPRINT> cert=<CERT> iat-mode=2
Bridge obfs4 <IP>:<PORT> <FOOTPRINT> cert=<CERT> iat-mode=0
Bridge obfs4 <IP>:<PORT> <FOOTPRINT> cert=<CERT> iat-mode=0
```

1. Start the service

```sh
docker run \
  --name tor \
  --publish 9050:9050 \
  --volume tor:/var/lib/tor \
  --volume ./bridges.conf:/etc/tor/torrc.d/bridges.conf \
  --detach \
  "$TOR_IMAGE"
```

### Hidden service example

1. Generate 2 addresses

```sh
docker run --volume onions:/root/mkp224o ghcr.io/vansergen/mkp224o -B -n 2 t
```

Output example:

```
set workdir: /root/mkp224o/
sorting filters... done.
filters:
        t
in total, 1 filter
using 4 threads
tidf4ursf562swhyvfx3wx755wwre6j573mvnynp6ztqapognm75iqid.onion
tc3tqrmytj3t2nh77q6fhcmsetegniq6u5t4vtwuku4jx7tayun4bwyd.onion
waiting for threads to finish... done.
```

2. Create configuration files
   - `torrc.d/tidf4ursf562swhyvfx3wx755wwre6j573mvnynp6ztqapognm75iqid.conf`

   ```apacheconf
   HiddenServiceDir /var/lib/tor/tidf4ursf562swhyvfx3wx755wwre6j573mvnynp6ztqapognm75iqid.onion
   HiddenServicePort 80 traefik:80 # <- Your proxy here
   HiddenServicePort 443 traefik:443 # <- Your proxy here
   ```

   - `torrc.d/tc3tqrmytj3t2nh77q6fhcmsetegniq6u5t4vtwuku4jx7tayun4bwyd.conf`

   ```apacheconf
   HiddenServiceDir /var/lib/tor/tc3tqrmytj3t2nh77q6fhcmsetegniq6u5t4vtwuku4jx7tayun4bwyd.onion
   HiddenServicePort 20022 nginx:22 # <- Your proxy here
   ```

3. Start the service

```sh
docker run --volume onions:/var/lib/tor --volume ${PWD}/torrc.d:/etc/tor/torrc.d --detach "$TOR_IMAGE"
```

#### Docker Compose example

- [`compose.yaml`](https://docs.docker.com/compose/compose-file/03-compose-file/):

```yaml
services:
  traefik:
    image: traefik:v3.0
    container_name: traefik
    # More traefik options
    networks:
      - tor

  tor:
    image: ghcr.io/vansergen/tor:2
    container_name: tor
    volumes:
      # Configuration files for hidden services
      - ./torrc.d:/etc/tor/torrc.d
      # Private/public keys for hidden services
      - onions:/var/lib/tor
    networks:
      - tor

  whoami:
    image: traefik/whoami:v1.9
    container_name: whoami
    networks:
      - tor

networks:
  tor:
    name: tor
```

## Upgrading from v1

Since v2 `tor` runs as the unprivileged `tor` user (uid `100`, gid `101`) instead of `root` and keeps its state in `/var/lib/tor`. v1 kept the client state (e.g. the guards) in `/root/.tor`, outside of the volume.

- Files mounted from the host (e.g. `torrc.d/*.conf`, `bridges.conf`) must be readable by uid `100`.
- `/etc/tor` is no longer declared as a volume. Mount `/etc/tor/torrc.d` (or `/etc/tor`) explicitly if you need to persist the configuration.

### Migrating a v1 container

The `tor-migrate` helper of the image backs up the volume, imports the state of v1 and changes the owner of the files. Keep the old container and the backups until v2 works.

0. Set the name of the existing v1 container and the volume mounted at its `/var/lib/tor`. They come from your v1 installation, not from the examples above.

```sh
CONTAINER=tor
VOLUME=onions
```

Check the volume with:

```sh
docker inspect -f '{{range .Mounts}}{{if eq .Destination "/var/lib/tor"}}{{.Name}}{{end}}{{end}}' "$CONTAINER"
```

1. Stop the old container and export its state into a new private directory (it contains the guards):

```sh
docker stop "$CONTAINER"
umask 077
BACKUP_DIR=$(mktemp -d "$HOME/tor-migration.XXXXXX")
docker cp "$CONTAINER":/root/.tor "$BACKUP_DIR/tor-state"
```

2. Back up the volume into a new volume (it contains the private keys of your onion services):

```sh
BACKUP_VOLUME="$VOLUME-backup-$(date +%Y%m%d%H%M%S)"
docker volume create "$BACKUP_VOLUME"
docker run --rm --user root --entrypoint tor-migrate --volume "$VOLUME":/var/lib/tor:ro --volume "$BACKUP_VOLUME":/backup "$TOR_IMAGE" backup
```

3. Import the state. On hosts with SELinux add `,z` to the options of the `/import` volume.

```sh
docker run --rm --user root --entrypoint tor-migrate --volume "$VOLUME":/var/lib/tor --volume "$BACKUP_DIR/tor-state":/import:ro "$TOR_IMAGE" import
```

The import refuses unexpected files (anything but regular files and directories with plain names, or without the tor `state` file) and files that already exist in the volume, without changing it. If it fails after it started copying, restore the volume from the backup:

```sh
docker run --rm --user root --entrypoint tor-migrate --volume "$BACKUP_VOLUME":/backup:ro --volume "$VOLUME":/var/lib/tor "$TOR_IMAGE" restore
```

4. Rename the old container and start v2 with the same volume and options:

```sh
docker rename "$CONTAINER" "$CONTAINER-v1"
```

5. Once v2 works, remove the old container and the backups:

```sh
docker rm "$CONTAINER-v1"
docker volume rm "$BACKUP_VOLUME"
rm -rf "$BACKUP_DIR"
```

Without the old container (and its state), only change the owner of the files in the volume:

```sh
docker run --rm --user root --entrypoint chown --volume "$VOLUME":/var/lib/tor "$TOR_IMAGE" -R tor:tor /var/lib/tor
```
