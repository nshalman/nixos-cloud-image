# Tests release-assets and prune-releases on fixtures, without the
# network. Needs both on the PATH, and jq and sha256sum.

set -o errexit -o nounset -o pipefail

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

failures=0
check() {
  local what=$1
  shift
  if "$@" > /dev/null; then
    echo "ok: $what"
  else
    echo "FAIL: $what"
    failures=$((failures + 1))
  fi
}

# release-assets

cat > "$work/info.json" <<'EOF'
{
  "channel": "stable",
  "tag": "26.05.20261026.718f670-fc06x6dk",
  "nixos_release": "26.05",
  "nixos_version": "26.05.20261026.718f670",
  "nixpkgs": { "ref": "nixos-26.05", "rev": "718f670e845328e9c2cecdd832835712b2cbd065" },
  "source_commit": "2751be8000000000000000000000000000000000"
}
EOF
mkdir "$work/image"
printf 'not really a qcow2\n' > "$work/image/nixos-image-efi-qcow2-26.05.20261026.718f670-x86_64-linux.qcow2"
want_sha=$(sha256sum < "$work/image/"*.qcow2 | cut -d ' ' -f 1)

release-assets "$work/info.json" "$work/image" "$work/out" || echo "release-assets exited $?"
asset=nixos-smartos-x86_64.qcow2

check "assets: the image under its fixed name" \
  cmp -s "$work/image/"*.qcow2 "$work/out/$asset"
check "assets: a GNU-style checksum file" \
  test "$(cat "$work/out/$asset.sha256")" = "$want_sha  $asset"
check "assets: image.json keeps the build info" \
  jq -e '.tag == "26.05.20261026.718f670-fc06x6dk" and .nixpkgs.rev == "718f670e845328e9c2cecdd832835712b2cbd065"' \
  "$work/out/image.json"
check "assets: image.json describes the image" \
  jq -e --arg sha "$want_sha" --arg asset "$asset" \
  '.image == {file: $asset, format: "qcow2", qcow2_cluster_compression: "zlib",
     arch: "x86_64", firmware: "uefi", datasources: ["nocloud"], size: 19, sha256: $sha}' \
  "$work/out/image.json"
check "assets: refuses to overwrite earlier assets" \
  bash -c '! release-assets "$1/info.json" "$1/image" "$1/out" 2> /dev/null' _ "$work"

# prune-releases

release() {
  printf '{"tagName": "%s", "isPrerelease": %s, "createdAt": "%s"}' "$1" "$2" "$3"
}
{
  echo "["
  release 25.11.20260501.aaaaaaa-fc06x6dk false 2026-05-01T00:00:00Z; echo ","
  release 26.05.20260601.bbbbbbb-fc06x6dk false 2026-06-01T00:00:00Z; echo ","
  release 26.05.20260701.ccccccc-fc06x6dk false 2026-07-01T00:00:00Z; echo ","
  release 26.05.20260801.ddddddd-fc06x6dk false 2026-08-01T00:00:00Z; echo ","
  release 26.05.20260901.eeeeeee-fc06x6dk false 2026-09-01T00:00:00Z; echo ","
  release 26.11.20261001.fffffff-fc06x6dk true 2026-10-01T00:00:00Z; echo ","
  release 26.11.20261008.0000000-fc06x6dk true 2026-10-08T00:00:00Z; echo ","
  release 26.11.20261015.1111111-fc06x6dk true 2026-10-15T00:00:00Z; echo ","
  release 26.11.20261022.2222222-fc06x6dk true 2026-10-22T00:00:00Z; echo ","
  release 26.11.20261029.3333333-fc06x6dk true 2026-10-29T00:00:00Z; echo ","
  release some-other-tag false 2020-01-01T00:00:00Z
  echo "]"
} > "$work/releases.json"

check "prune: the oldest stable beyond 3 per series and unstable beyond 4" \
  test "$(prune-releases < "$work/releases.json")" = \
  "$(printf '%s\n' 26.05.20260601.bbbbbbb-fc06x6dk 26.11.20261001.fffffff-fc06x6dk)"
check "prune: other keep counts" \
  test "$(prune-releases --keep-stable 1 --keep-unstable 5 < "$work/releases.json")" = \
  "$(printf '%s\n' 26.05.20260601.bbbbbbb-fc06x6dk 26.05.20260701.ccccccc-fc06x6dk 26.05.20260801.ddddddd-fc06x6dk)"
check "prune: nothing to delete prints nothing" \
  test -z "$(echo '[]' | prune-releases)"

if [ "$failures" -ne 0 ]; then
  echo "release-scripts-test: $failures test(s) failed"
  exit 1
fi
echo "release-scripts-test: all tests passed"
