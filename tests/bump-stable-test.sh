# Tests bump-stable on a copy of the repository's flake.nix, passed as
# $1, without the network (--no-lock). Needs bump-stable on the PATH.

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

cp "$1" "$work/flake.nix"
chmod u+w "$work/flake.nix"
cp "$work/flake.nix" "$work/before.nix"
bump-stable 99.11 --flake "$work/flake.nix" --no-lock || echo "bump-stable exited $?"

check "the stable input follows the new channel" \
  grep -q -F 'inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-99.11";' "$work/flake.nix"
check "nothing else changed" \
  test "$(diff "$work/before.nix" "$work/flake.nix" | grep -c '^[<>]')" = 2
check "the unstable input is untouched" \
  grep -q -F 'inputs.nixpkgs-unstable.url = "github:NixOS/nixpkgs/nixos-unstable";' "$work/flake.nix"

cp "$work/before.nix" "$work/flake.nix"
check "a malformed version is refused" \
  bash -c '! bump-stable 99.1 --flake "$1" --no-lock 2> /dev/null' _ "$work/flake.nix"
check "a refused bump leaves the file alone" cmp -s "$work/before.nix" "$work/flake.nix"

echo 'inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";' > "$work/other.nix"
check "a file without a stable channel URL is refused" \
  bash -c '! bump-stable 99.11 --flake "$1" --no-lock 2> /dev/null' _ "$work/other.nix"

if [ "$failures" -ne 0 ]; then
  echo "bump-stable-test: $failures test(s) failed"
  exit 1
fi
echo "bump-stable-test: all tests passed"
