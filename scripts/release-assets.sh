# Writes a release's assets into OUTDIR under fixed names, so a client can
# find them in any release: the image, its checksum (GNU format) and
# image.json, which is release-info's output plus a description of the
# image.
#
# Usage: release-assets INFO IMAGE OUTDIR
#   INFO    release-info's JSON for this build
#   IMAGE   the qcow2 image, or a directory holding one (nix build's output)
#   OUTDIR  where to write the assets; must not hold them already

if [ $# -ne 3 ]; then
  echo "usage: release-assets INFO IMAGE OUTDIR" >&2
  exit 2
fi
info=$1
image=$2
out=$3
asset=nixos-smartos-x86_64.qcow2

if [ -d "$image" ]; then
  image=$(find -L "$image" -maxdepth 1 -name '*.qcow2' | head -n 1)
fi
if [ ! -f "$image" ]; then
  echo "release-assets: no qcow2 image at '$2'" >&2
  exit 2
fi
if [ -e "$out/$asset" ] || [ -e "$out/$asset.sha256" ] || [ -e "$out/image.json" ]; then
  echo "release-assets: $out already holds release assets" >&2
  exit 2
fi

mkdir -p "$out"
cp "$image" "$out/$asset"
chmod u+w "$out/$asset"
sha=$(sha256sum < "$out/$asset" | cut -d ' ' -f 1)
echo "$sha  $asset" > "$out/$asset.sha256"
jq --arg file "$asset" --arg sha "$sha" --argjson size "$(stat -c %s "$out/$asset")" \
  '. + {image: {file: $file, format: "qcow2", qcow2_cluster_compression: "zlib",
    arch: "x86_64", firmware: "uefi", datasources: ["nocloud"],
    size: $size, sha256: $sha}}' "$info" > "$out/image.json"
