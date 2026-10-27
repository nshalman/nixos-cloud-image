# Says whether the flake's stable input still follows the newest NixOS
# release. nixpkgs tags each release YY.MM when it ships (and YY.MM-beta
# at branch-off, which does not count), so a YY.MM tag newer than the
# input's nixos-YY.MM channel means a newer stable has been released.
#
# Usage: check-stable [--lock FILE] [--tags FILE] [--newest]
#   --lock    the flake.lock to read (default: ./flake.lock)
#   --tags    a file of nixpkgs tag names, one per line (default: read
#             from the nixpkgs repository with git ls-remote)
#   --newest  print only the newest release (YY.MM), without reading the
#             lock, and exit 0
#
# Exits 0 when the stable input is the newest release, 1 when a newer
# release has been tagged, and 2 when it cannot tell.

lock=flake.lock
tags=
newest_only=

while [ $# -gt 0 ]; do
  case $1 in
    --lock) lock=$2; shift 2 ;;
    --tags) tags=$2; shift 2 ;;
    --newest) newest_only=1; shift ;;
    *) echo "check-stable: unknown argument: $1" >&2; exit 2 ;;
  esac
done

if [ -n "$tags" ]; then
  tag_names=$(cat "$tags")
else
  tag_names=$(git ls-remote --tags --refs https://github.com/NixOS/nixpkgs \
    'refs/tags/[0-9][0-9].[0-9][0-9]' | cut -f 2 | sed 's|^refs/tags/||')
fi

newest=$(grep -E '^[0-9]{2}\.[0-9]{2}$' <<< "$tag_names" | sort -V | tail -n 1) || true
if [ -z "$newest" ]; then
  echo "check-stable: found no NixOS release tags (YY.MM) in nixpkgs" >&2
  exit 2
fi

if [ -n "$newest_only" ]; then
  echo "$newest"
  exit 0
fi

if ! node=$(jq -r -e '.nodes[.root].inputs.nixpkgs' "$lock") ||
  ! ref=$(jq -r -e --arg node "$node" '.nodes[$node].original.ref' "$lock"); then
  echo "check-stable: cannot read the nixpkgs input's ref from $lock" >&2
  exit 2
fi

if ! [[ $ref =~ ^nixos-([0-9]{2}\.[0-9]{2})$ ]]; then
  echo "check-stable: the nixpkgs input follows $ref, which is not a NixOS release channel" >&2
  exit 2
fi
current=${BASH_REMATCH[1]}

if [ "$(printf '%s\n' "$current" "$newest" | sort -V | tail -n 1)" = "$current" ]; then
  echo "check-stable: $ref is the newest NixOS release ($newest)"
  exit 0
fi

echo "check-stable: $ref is behind: NixOS $newest has been released." \
  "Point inputs.nixpkgs at github:NixOS/nixpkgs/nixos-$newest and run" \
  "nix flake update nixpkgs."
exit 1
