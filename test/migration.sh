#!/bin/sh
# Checks the migration of a v1 container: test/migration.sh IMAGE [TOR_ARGS...]
#
# CONTAINER_ENGINE: docker (default) or podman
# OLD_IMAGE: the v1 image (ghcr.io/vansergen/tor:1.2.12 by default)
# TOR_ARGS are passed to tor in the started containers, e.g.
# `--SocksPort 0.0.0.0:9050` on hosts without IPv6.
set -eu

[ $# -ge 1 ] || {
  echo "usage: $0 IMAGE [TOR_ARGS...]" >&2
  exit 2
}
IMAGE=$1
shift
OLD_IMAGE=${OLD_IMAGE:-ghcr.io/vansergen/tor:1.2.12}

# shellcheck source=test/lib.sh
. "$(dirname "$0")/lib.sh"

ID=tor-test-migration-$$
VOLUME=$ID-data
BACKUP_VOLUME=$ID-backup
umask 077
BACKUP_DIR=$(mktemp -d)
WORK=$(mktemp -d)

cleanup() {
  "$ENGINE" rm -f "$ID-v1" "$ID-v2" "$ID-base" "$ID-run" > /dev/null 2>&1 || true
  "$ENGINE" volume rm -f "$VOLUME" "$BACKUP_VOLUME" "$ID-empty" "$ID-incomplete" \
    "$ID-fake" "$ID-hashfail" "$ID-fifo" > /dev/null 2>&1 || true
  rm -rf "$BACKUP_DIR" "$WORK"
}
trap cleanup EXIT
trap 'exit 1' HUP INT TERM

# Runs `tor-migrate SUBCOMMAND` with the mount options, which must fail with
# the reason and change neither the volume nor anything in the container
# but its temporary directory
expect_refusal() {
  name=$1 reason=$2 vol=$3 subcommand=$4
  shift 4
  before=$(snapshot "$vol")

  # The changes of a container that does nothing, e.g. the mount points
  "$ENGINE" run --name "$ID-base" --network none --user root --entrypoint true "$@" "$IMAGE"
  { "$ENGINE" diff "$ID-base" && echo "C /tmp"; } > "$WORK/expected"
  "$ENGINE" rm "$ID-base" > /dev/null

  if "$ENGINE" run --name "$ID-run" --network none --user root --entrypoint tor-migrate \
    "$@" "$IMAGE" "$subcommand" > "$WORK/out" 2>&1; then
    cat "$WORK/out" >&2
    fail "$name: accepted"
  fi
  grep -qF "$reason" "$WORK/out" || {
    cat "$WORK/out" >&2
    fail "$name: refused for another reason"
  }
  changes=$("$ENGINE" diff "$ID-run") || fail "$name: cannot list the changes of the container"
  "$ENGINE" rm "$ID-run" > /dev/null
  unexpected=
  while IFS= read -r line; do
    [ -n "$line" ] || continue
    grep -qxF -- "$line" "$WORK/expected" || unexpected="$unexpected
$line"
  done << EOF
$changes
EOF
  [ -z "$unexpected" ] || fail "$name: changed the container: $unexpected"
  [ "$(snapshot "$vol")" = "$before" ] || fail "$name: changed the volume $vol"
  echo "refused $name: $(sed -n 1p "$WORK/out")"
}

log "run v1 ($OLD_IMAGE) with a hidden service"
write_torrc_d "$WORK/torrc.d" hs
"$ENGINE" run --detach --name "$ID-v1" --network none --volume "$VOLUME":/var/lib/tor \
  --volume "$WORK/torrc.d":/etc/tor/torrc.d:ro "$OLD_IMAGE" "$@" > /dev/null
wait_ready "$ID-v1"
address=$(on_volume "$VOLUME" 'cat /v/hs/hostname')
log "v1 runs $address"

log "stop v1 and export its state"
"$ENGINE" stop "$ID-v1" > /dev/null
"$ENGINE" cp "$ID-v1":/root/.tor "$BACKUP_DIR/tor-state"
public=$(find "$BACKUP_DIR" \( -perm -g=r -o -perm -g=w -o -perm -g=x \
  -o -perm -o=r -o -perm -o=w -o -perm -o=x \) -print)
[ -z "$public" ] || fail "readable by others: $public"

log "back up the volume"
"$ENGINE" volume create "$BACKUP_VOLUME" > /dev/null
"$ENGINE" run --rm --network none --user root --entrypoint tor-migrate \
  --volume "$VOLUME":/var/lib/tor:ro --volume "$BACKUP_VOLUME":/backup "$IMAGE" backup
on_volume "$BACKUP_VOLUME" 'test -f /v/complete && test -f /v/data/hs/hs_ed25519_secret_key' ||
  fail "incomplete backup"
original=$(snapshot "$VOLUME")

log "refuse unusable exports"
state=$BACKUP_DIR/tor-state/state
bad() {
  dir=$WORK/$1
  mkdir "$dir"
  [ "$2" = no-state ] || cp "$state" "$dir/state"
  printf '%s\n' "$dir"
}
d=$(bad no-state no-state)
echo x > "$d/cached-certs"
expect_refusal "an export without a state" "has no tor state file" "$VOLUME" import \
  --volume "$VOLUME":/var/lib/tor --volume "$d":/import:ro
d=$(bad empty-state no-state)
: > "$d/state"
expect_refusal "an empty state" "has no tor state file" "$VOLUME" import \
  --volume "$VOLUME":/var/lib/tor --volume "$d":/import:ro
d=$(bad symlink-dir state)
ln -s /var/lib/tor "$d/link"
expect_refusal "a symlink to a directory" "unsupported files" "$VOLUME" import \
  --volume "$VOLUME":/var/lib/tor --volume "$d":/import:ro
d=$(bad symlink-file state)
ln -s /etc/passwd "$d/link"
expect_refusal "a symlink to a file" "unsupported files" "$VOLUME" import \
  --volume "$VOLUME":/var/lib/tor --volume "$d":/import:ro
d=$(bad hardlink state)
ln "$d/state" "$d/link"
expect_refusal "a hard link" "unsupported files" "$VOLUME" import \
  --volume "$VOLUME":/var/lib/tor --volume "$d":/import:ro
# A FIFO of the host may not be usable through a bind mount (e.g. with
# Podman on macOS), so make it in a volume
"$ENGINE" volume create "$ID-fifo" > /dev/null
"$ENGINE" run --rm --network none --user root --entrypoint sh --volume "$ID-fifo":/v \
  --volume "$BACKUP_DIR/tor-state":/export:ro "$IMAGE" -euc 'cp /export/state /v/state && mkfifo /v/fifo'
expect_refusal "a FIFO" "unsupported files" "$VOLUME" import \
  --volume "$VOLUME":/var/lib/tor --volume "$ID-fifo":/import:ro
d=$(bad newline state)
echo x > "$d/$(printf 'new\nline')"
expect_refusal "a name with a newline" "unsupported files" "$VOLUME" import \
  --volume "$VOLUME":/var/lib/tor --volume "$d":/import:ro
d=$(bad space state)
echo x > "$d/with space"
expect_refusal "a name with a space" "unsupported files" "$VOLUME" import \
  --volume "$VOLUME":/var/lib/tor --volume "$d":/import:ro

log "refuse unusable backups"
"$ENGINE" volume create "$ID-empty" > /dev/null
expect_refusal "an empty backup" "not a complete backup" "$VOLUME" restore \
  --volume "$ID-empty":/backup:ro --volume "$VOLUME":/var/lib/tor
"$ENGINE" volume create "$ID-incomplete" > /dev/null
"$ENGINE" run --rm --network none --user root --entrypoint tor-migrate \
  --volume "$VOLUME":/var/lib/tor:ro --volume "$ID-incomplete":/backup "$IMAGE" backup > /dev/null
on_volume "$ID-incomplete" 'rm /v/complete'
expect_refusal "a backup without the complete mark" "not a complete backup" "$VOLUME" restore \
  --volume "$ID-incomplete":/backup:ro --volume "$VOLUME":/var/lib/tor
expect_refusal "a backup into a used volume" "is not empty" "$BACKUP_VOLUME" backup \
  --volume "$VOLUME":/var/lib/tor:ro --volume "$BACKUP_VOLUME":/backup

log "refuse to back up or restore when hashing fails"
# A sha256sum that always fails, first in PATH
"$ENGINE" volume create "$ID-fake" > /dev/null
on_volume "$ID-fake" 'printf "#!/bin/sh\nexit 1\n" > /v/sha256sum && chmod 755 /v/sha256sum'
FAKE_PATH=/fake:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
# The backup copies the data before it verifies it, so its volume changes,
# but it must not be marked complete
"$ENGINE" volume create "$ID-hashfail" > /dev/null
before=$(snapshot "$VOLUME")
if "$ENGINE" run --rm --network none --user root --entrypoint tor-migrate \
  --volume "$ID-fake":/fake:ro --env "PATH=$FAKE_PATH" --volume "$VOLUME":/var/lib/tor:ro \
  --volume "$ID-hashfail":/backup "$IMAGE" backup > "$WORK/out" 2>&1; then
  cat "$WORK/out" >&2
  fail "a backup with a failing sha256sum: accepted"
fi
grep -qF "cannot verify the backup" "$WORK/out" || {
  cat "$WORK/out" >&2
  fail "a backup with a failing sha256sum: refused for another reason"
}
on_volume "$ID-hashfail" 'test ! -e /v/complete' ||
  fail "a backup with a failing sha256sum is marked complete"
[ "$(snapshot "$VOLUME")" = "$before" ] || fail "a backup with a failing sha256sum changed $VOLUME"
echo "refused a backup with a failing sha256sum: $(sed -n 1p "$WORK/out")"
expect_refusal "a restore with a failing sha256sum" "cannot verify the backup" "$VOLUME" restore \
  --volume "$ID-fake":/fake:ro --env "PATH=$FAKE_PATH" \
  --volume "$BACKUP_VOLUME":/backup:ro --volume "$VOLUME":/var/lib/tor

log "import the state"
"$ENGINE" run --rm --network none --user root --entrypoint tor-migrate \
  --volume "$VOLUME":/var/lib/tor --volume "$BACKUP_DIR/tor-state":/import:ro "$IMAGE" import
"$ENGINE" run --rm --network none --user root --entrypoint cmp \
  --volume "$VOLUME":/var/lib/tor:ro --volume "$BACKUP_DIR/tor-state":/import:ro \
  "$IMAGE" /import/state /var/lib/tor/state || fail "the imported state differs from the export"
owners=$(on_volume "$VOLUME" 'find /v ! -user tor')
[ -z "$owners" ] || fail "not owned by tor: $owners"
expect_refusal "an existing state" "already in /var/lib/tor" "$VOLUME" import \
  --volume "$VOLUME":/var/lib/tor --volume "$BACKUP_DIR/tor-state":/import:ro

log "restore the backup"
"$ENGINE" run --rm --network none --user root --entrypoint tor-migrate \
  --volume "$BACKUP_VOLUME":/backup:ro --volume "$VOLUME":/var/lib/tor "$IMAGE" restore
[ "$(snapshot "$VOLUME")" = "$original" ] || fail "the restored volume differs from the original"

log "import the state again and run v2"
"$ENGINE" run --rm --network none --user root --entrypoint tor-migrate \
  --volume "$VOLUME":/var/lib/tor --volume "$BACKUP_DIR/tor-state":/import:ro "$IMAGE" import
"$ENGINE" run --detach --name "$ID-v2" --network none --volume "$VOLUME":/var/lib/tor \
  --volume "$WORK/torrc.d":/etc/tor/torrc.d:ro "$IMAGE" "$@" > /dev/null
wait_ready "$ID-v2"
hostname=$(on_volume "$VOLUME" 'cat /v/hs/hostname')
[ "$hostname" = "$address" ] || fail "v2 runs $hostname instead of $address"
on_volume "$VOLUME" 'test -f /v/lock' || fail "no lock file in /var/lib/tor"
on_volume "$VOLUME" 'test ! -e /v/.tor' || fail "tor keeps its state in /var/lib/tor/.tor"

log "OK"
