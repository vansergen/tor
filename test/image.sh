#!/bin/sh
# Checks an image of tor: test/image.sh IMAGE [TOR_ARGS...]
#
# CONTAINER_ENGINE: docker (default) or podman
# MKP224O_PLATFORM: platform of the mkp224o image (e.g. linux/amd64)
# TOR_ARGS are passed to tor in the started containers, e.g.
# `--SocksPort 0.0.0.0:9050` on hosts without IPv6.
set -eu

[ $# -ge 1 ] || {
  echo "usage: $0 IMAGE [TOR_ARGS...]" >&2
  exit 2
}
IMAGE=$1
shift

# shellcheck source=test/lib.sh
. "$(dirname "$0")/lib.sh"

ID=tor-test-image-$$
VOLUME=$ID
WORK=$(mktemp -d)

cleanup() {
  "$ENGINE" rm -f "$ID-1" "$ID-2" > /dev/null 2>&1 || true
  "$ENGINE" volume rm -f "$VOLUME" > /dev/null 2>&1 || true
  rm -rf "$WORK"
}
trap cleanup EXIT
trap 'exit 1' HUP INT TERM

log "versions"
"$ENGINE" run --rm --network none --entrypoint tor "$IMAGE" --version | sed -n 1p
"$ENGINE" run --rm --network none --entrypoint lyrebird "$IMAGE" -version

log "the bundled configuration is valid"
"$ENGINE" run --rm --network none "$IMAGE" --verify-config > /dev/null

log "tor runs as the tor user"
user=$("$ENGINE" run --rm --network none --entrypoint id "$IMAGE" -un)
[ "$user" = tor ] || fail "runs as $user"

log "generate keys with mkp224o"
# shellcheck disable=SC2086 # no --platform without MKP224O_PLATFORM
"$ENGINE" run --rm --network none ${MKP224O_PLATFORM:+--platform "$MKP224O_PLATFORM"} \
  --volume "$VOLUME":/root/mkp224o ghcr.io/vansergen/mkp224o -n 1 -t 1 t > /dev/null
address=$(on_volume "$VOLUME" 'cd /v && ls -d -- *.onion')
log "generated $address"
owner=$(on_volume "$VOLUME" "stat -c %U /v/$address/hs_ed25519_secret_key")
[ "$owner" = root ] || fail "the generated keys are owned by $owner"
write_torrc_d "$WORK/torrc.d" "$address"

log "tor cannot read the keys of root"
if out=$("$ENGINE" run --rm --network none --volume "$VOLUME":/var/lib/tor \
  --volume "$WORK/torrc.d":/etc/tor/torrc.d:ro "$IMAGE" --verify-config "$@" 2>&1); then
  fail "the configuration is valid with keys of root"
fi
case $out in
  *"Directory /var/lib/tor/$address cannot be read: Permission denied"*) ;;
  *)
    echo "$out" >&2
    fail "unexpected error with keys of root"
    ;;
esac

log "change the owner of the keys"
"$ENGINE" run --rm --network none --user root --entrypoint chown \
  --volume "$VOLUME":/var/lib/tor "$IMAGE" -R tor:tor /var/lib/tor
# tor writes it again from the keys
on_volume "$VOLUME" "rm /v/$address/hostname"

for n in 1 2; do
  log "start tor ($n)"
  "$ENGINE" run --detach --name "$ID-$n" --network none --volume "$VOLUME":/var/lib/tor \
    --volume "$WORK/torrc.d":/etc/tor/torrc.d:ro "$IMAGE" "$@" > /dev/null
  wait_ready "$ID-$n"
  hostname=$(on_volume "$VOLUME" "cat /v/$address/hostname")
  [ "$hostname" = "$address" ] || fail "the hostname is $hostname instead of $address"
  on_volume "$VOLUME" 'test -f /v/lock' || fail "no lock file in /var/lib/tor"
  on_volume "$VOLUME" 'test ! -e /v/.tor' || fail "tor keeps its state in /var/lib/tor/.tor"

  log "recreate the container ($n)"
  "$ENGINE" stop "$ID-$n" > /dev/null
  "$ENGINE" rm "$ID-$n" > /dev/null
  on_volume "$VOLUME" 'test -s /v/state' || fail "no state in /var/lib/tor"
done

log "OK"
