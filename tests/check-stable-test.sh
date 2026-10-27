# Tests check-stable against fixture lock files and tag lists, without
# the network. Needs check-stable on the PATH.

set -o errexit -o nounset -o pipefail

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

lock() {
  cat > "$work/flake.lock" <<EOF
{
  "nodes": {
    "nixpkgs_2": {
      "original": { "owner": "NixOS", "ref": "$1", "repo": "nixpkgs", "type": "github" }
    },
    "root": { "inputs": { "nixpkgs": "nixpkgs_2" } }
  },
  "root": "root",
  "version": 7
}
EOF
}

tags() {
  printf '%s\n' "$@" > "$work/tags"
}

failures=0
expect() {
  local what=$1 status=$2 pattern=$3 output actual=0
  output=$(check-stable --lock "$work/flake.lock" --tags "$work/tags" 2>&1) || actual=$?
  if [ "$actual" -eq "$status" ] && grep -q -E -- "$pattern" <<< "$output"; then
    echo "ok: $what"
  else
    echo "FAIL: $what: exit $actual (wanted $status), output:"
    echo "$output"
    failures=$((failures + 1))
  fi
}

lock nixos-26.05
tags 25.05 25.11 26.05 25.11-beta 26.05-beta
expect "current stable is up to date" 0 'nixos-26.05 is the newest NixOS release'

tags 25.11 26.05 26.05-beta 26.11-beta
expect "a beta tag is not a release" 0 'nixos-26.05 is the newest NixOS release'

tags 25.11 26.05 26.11 26.11-beta
expect "a newer release is reported" 1 'NixOS 26\.11 has been released.*nixos-26\.11'

tags 26.05 26.11 27.05
expect "the newest of several newer releases is named" 1 'NixOS 27\.05 has been released'

lock nixos-unstable
tags 26.05
expect "a non-release ref is an error" 2 'not a NixOS release channel'

lock nixos-26.05
tags
expect "no release tags is an error" 2 'no NixOS release tags'

if [ "$failures" -ne 0 ]; then
  echo "check-stable-test: $failures test(s) failed"
  exit 1
fi
echo "check-stable-test: all tests passed"
