# shellcheck shell=sh
# Shared by the image tests (test/*.sh), sourced after IMAGE is set
#
# CONTAINER_ENGINE: docker (default) or podman

ENGINE=${CONTAINER_ENGINE:-docker}

log() {
  echo "==> $*"
}

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

# Runs a shell command as root with a volume mounted at /v
on_volume() {
  vol=$1
  shift
  "$ENGINE" run --rm --network none --user root --entrypoint sh \
    --volume "$vol":/v "$IMAGE" -euc "$@"
}

# Lists the entries of a volume with their type, owner, mode, size and hash
snapshot() {
  on_volume "$1" '
    cd /v
    find . -exec stat -c "%F %u %g %a %s %n" {} + | sort
    find . -type f -exec sha256sum {} + | sort'
}

# Waits up to 30 seconds until tor in a container has finished its
# initialization, then checks that it keeps running without errors. Tor does
# not need to reach the network.
wait_ready() {
  i=0
  until "$ENGINE" logs "$1" 2>&1 | grep -q 'Bootstrapped 0% (starting): Starting'; do
    i=$((i + 1))
    if [ "$i" -gt 30 ] || [ "$("$ENGINE" inspect -f '{{.State.Running}}' "$1")" != true ]; then
      "$ENGINE" logs "$1" >&2 || true
      fail "$1 did not finish its initialization"
    fi
    sleep 1
  done
  sleep 5
  if [ "$("$ENGINE" inspect -f '{{.State.Running}}' "$1")" != true ] ||
    "$ENGINE" logs "$1" 2>&1 | grep -q '\[err\]'; then
    "$ENGINE" logs "$1" >&2 || true
    fail "$1 failed after its initialization"
  fi
}

# Writes a torrc.d directory with a hidden service in /var/lib/tor/$2
write_torrc_d() {
  mkdir -p "$1"
  printf 'HiddenServiceDir /var/lib/tor/%s\nHiddenServicePort 80 127.0.0.1:80\n' "$2" > "$1/hs.conf"
  # Readable by the tor user of the image
  chmod 755 "$1"
  chmod 644 "$1/hs.conf"
}
