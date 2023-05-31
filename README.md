# Tor [![code style: prettier](https://img.shields.io/badge/code_style-prettier-ff69b4.svg)](https://github.com/prettier/prettier) [![Contributor Covenant](https://img.shields.io/badge/Contributor%20Covenant-2.1-4baaaa.svg)](CODE_OF_CONDUCT.md) [![semantic-release](https://img.shields.io/badge/%20%20%F0%9F%93%A6%F0%9F%9A%80-semantic--release-e10079.svg)](https://github.com/semantic-release/semantic-release) [![Conventional Commits](https://img.shields.io/badge/Conventional%20Commits-1.0.0-yellow.svg)](https://conventionalcommits.org)

A simple docker container to access the [Tor](https://www.torproject.org/) network.

## Usage

### SOCKS proxy

Start the service

```sh
docker run --publish 9050:9050 --detach ghcr.io/vansergen/tor
```

Test the connection

```sh
curl --socks5-hostname localhost:9050 https://api64.ipify.org
```

### Hidden service

1. Generate an address

```sh
docker run --volume onions:/root/mkp224o ghcr.io/vansergen/mkp224o -B -n 1 t
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
waiting for threads to finish... done.
```

2. Create a configuration file `torrc.d/tidf4ursf562swhyvfx3wx755wwre6j573mvnynp6ztqapognm75iqid.conf`

```apacheconf
HiddenServiceDir /var/lib/tor/tidf4ursf562swhyvfx3wx755wwre6j573mvnynp6ztqapognm75iqid.onion
HiddenServicePort 80 traefik:80 # <- Your proxy here
HiddenServicePort 443 traefik:443 # <- Your proxy here
```

3. Start the service

```sh
docker run --volume onions:/var/lib/tor --volume ./torrc.d:/etc/tor/torrc.d --detach ghcr.io/vansergen/tor
```

3.1. Docker Compose example

```yaml
services:
  traefik:
    image: traefik:v3.0
    container_name: traefik
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
