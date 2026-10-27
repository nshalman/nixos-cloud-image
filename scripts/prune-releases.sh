# Reads the repository's releases, as `gh release list --json
# tagName,isPrerelease,createdAt` prints them, and prints the tags of the
# ones beyond those to keep: the newest few of each stable series (by the
# YY.MM their tag starts with) and of unstable (the pre-releases). Tags
# that do not look like this repository's releases are never listed.
#
# Usage: prune-releases [--keep-stable N] [--keep-unstable N] < releases.json

keep_stable=3
keep_unstable=4

while [ $# -gt 0 ]; do
  case $1 in
    --keep-stable) keep_stable=$2; shift 2 ;;
    --keep-unstable) keep_unstable=$2; shift 2 ;;
    *) echo "prune-releases: unknown argument: $1" >&2; exit 2 ;;
  esac
done

jq -r --argjson stable "$keep_stable" --argjson unstable "$keep_unstable" '
  [.[] | select(.tagName | test("^[0-9]{2}\\.[0-9]{2}\\.[0-9]{8}\\.[0-9a-f]+-g[0-9a-f]+$"))] as $ours
  | ([$ours[] | select(.isPrerelease | not)]
      | group_by(.tagName[0:5])
      | map(sort_by(.createdAt) | reverse | .[$stable:])
      | add // [])
    + ([$ours[] | select(.isPrerelease)] | sort_by(.createdAt) | reverse | .[$unstable:])
  | .[].tagName
' | sort
