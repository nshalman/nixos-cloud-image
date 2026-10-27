# Points the flake's stable input (inputs.nixpkgs) at the channel of a new
# NixOS release, nixos-VERSION, and updates flake.lock to its head.
#
# Usage: bump-stable VERSION [--flake FILE] [--no-lock]
#   VERSION    the release, YY.MM (check-stable --newest prints it)
#   --flake    the flake.nix to edit (default: ./flake.nix)
#   --no-lock  edit flake.nix only; leave flake.lock alone
#
# Uses the nix on the PATH to update the lock.

version=
flake=flake.nix
update_lock=1

while [ $# -gt 0 ]; do
  case $1 in
    --flake) flake=$2; shift 2 ;;
    --no-lock) update_lock=; shift ;;
    -*) echo "bump-stable: unknown argument: $1" >&2; exit 2 ;;
    *) version=$1; shift ;;
  esac
done

if ! [[ $version =~ ^[0-9]{2}\.[0-9]{2}$ ]]; then
  echo "usage: bump-stable VERSION [--flake FILE] [--no-lock], with VERSION as YY.MM" >&2
  exit 2
fi

pattern='^(  inputs\.nixpkgs\.url = "github:NixOS/nixpkgs/nixos-)[0-9]{2}\.[0-9]{2}(";)$'
count=$(grep -c -E "$pattern" "$flake") || true
if [ "$count" != 1 ]; then
  echo "bump-stable: expected one stable channel URL (inputs.nixpkgs.url) in $flake, found ${count:-0}" >&2
  exit 2
fi

sed -i -E "s|$pattern|\1$version\2|" "$flake"

if [ -n "$update_lock" ]; then
  (cd "$(dirname "$flake")" && nix flake update nixpkgs)
fi
