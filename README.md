# Tor [![code style: prettier](https://img.shields.io/badge/code_style-prettier-ff69b4.svg)](https://github.com/prettier/prettier) [![Contributor Covenant](https://img.shields.io/badge/Contributor%20Covenant-2.1-4baaaa.svg)](CODE_OF_CONDUCT.md) [![semantic-release](https://img.shields.io/badge/%20%20%F0%9F%93%A6%F0%9F%9A%80-semantic--release-e10079.svg)](https://github.com/semantic-release/semantic-release) [![Conventional Commits](https://img.shields.io/badge/Conventional%20Commits-1.0.0-yellow.svg)](https://conventionalcommits.org)

A simple docker container to access the [Tor](https://www.torproject.org/) network.

## Usage

### SOCKS proxy example

1. Start the service

```sh
docker run --publish 9050:9050 --detach ghcr.io/vansergen/tor
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
  --publish 9050:9050 \
  --volume ./bridges.conf:/etc/tor/torrc.d/bridges.conf \
  --detach \
  ghcr.io/vansergen/tor
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
docker run --volume onions:/var/lib/tor --volume ${PWD}/torrc.d:/etc/tor/torrc.d --detach ghcr.io/vansergen/tor
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
    image: ghcr.io/vansergen/tor:latest
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
