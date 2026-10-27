# Prints, as JSON, what identifies the release that this checkout would
# build for CHANNEL (stable or unstable): the NixOS version and nixpkgs
# revision from flake.lock, the source commit, the image's derivation,
# and the release tag, <NixOS version>-<first 8 characters of the
# derivation's hash>. A build whose tag already exists has been released:
# the same derivation is the same image, whatever else changed in the
# repository.
#
# Usage: release-info CHANNEL [--update]
#   --update  first update CHANNEL's input in flake.lock to the head of its
#             channel (nix flake update), as a scheduled build does
#
# Run it from the flake's checkout. Uses the nix on the PATH.

if [ $# -lt 1 ] || [ $# -gt 2 ] || { [ $# -eq 2 ] && [ "$2" != --update ]; }; then
  echo "usage: release-info CHANNEL [--update]" >&2
  exit 2
fi
channel=$1

case $channel in
  stable) input=nixpkgs ;;
  unstable) input=nixpkgs-unstable ;;
  *) echo "release-info: unknown channel '$channel' (stable or unstable)" >&2; exit 2 ;;
esac

if [ $# -eq 2 ]; then
  nix flake update "$input" >&2
fi

node=$(jq -r -e --arg input "$input" '.nodes[.root].inputs[$input]' flake.lock)
version=$(nix eval --raw ".#nixosConfigurations.$channel.config.system.nixos.label")
release=$(nix eval --raw ".#nixosConfigurations.$channel.config.system.nixos.release")
drv=$(nix eval --raw ".#packages.x86_64-linux.$channel.drvPath")
hash=$(basename "$drv")
commit=$(git rev-parse HEAD)

jq -n \
  --arg channel "$channel" \
  --arg tag "$version-${hash:0:8}" \
  --arg release "$release" \
  --arg version "$version" \
  --arg drv "$drv" \
  --arg commit "$commit" \
  --argjson nixpkgs "$(jq --arg node "$node" \
    '.nodes[$node] | {ref: .original.ref, rev: .locked.rev}' flake.lock)" \
  '{channel: $channel, tag: $tag, nixos_release: $release, nixos_version: $version,
    nixpkgs: $nixpkgs, image_drv: $drv, source_commit: $commit}'
