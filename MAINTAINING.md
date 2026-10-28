# Maintaining nixos-cloud-image

## Build

There are two images, from the same modules: `stable`, from the current
NixOS release's channel (the `nixpkgs` input), and
`unstable`, from `nixos-unstable` (the `nixpkgs-unstable` input).

    nix build .#stable
    nix build .#unstable

`result/` then holds the compressed qcow2 image. `nix build` alone builds
`stable`.

## Is stable still the newest release?

    nix run .#check-stable

Exits 0 if the `nixpkgs` input follows the newest NixOS release, and 1,
naming the new channel, once nixpkgs has tagged a newer one (`YY.MM`;
the `YY.MM-beta` branch-off tag does not count). Exits 2 when it cannot
tell. With `--newest` it prints only the newest release. `nix build
.#checks.x86_64-linux.check-stable` runs its tests.

## Test

    nix run .#boot-test -- "$(nix build .#stable --no-link --print-out-paths)"

Boots the image (`stable` here; likewise `unstable`) under QEMU with
OVMF the way
SmartOS boots a bhyve guest: UEFI with no saved boot entries, virtio disk
and NIC, and a 16 MiB FAT16 `CIDATA` disk holding `tests/cidata`, which
is in the format smartos-live's `nocloud.js` writes. It checks over SSH
that cloud-init applied all of it, reboots, and checks again. Needs KVM.

## Releases

When the build updated the lock, the commit a release's tag points at
is on no branch.

- `build.yml` builds from the head of each channel: unstable weekly,
  stable monthly and on every push to `main`. It skips images released
  already, boot-tests the rest before releasing them, and keeps the newest
  3 releases of each stable series and 4 of unstable.
  After each run it publishes an index of the current releases (see
  below).
- `check-stable.yml` runs daily. When NixOS tags a newer release, it opens
  a pull request moving the stable input to it, with the result of
  building and boot-testing that image.
- `ci.yml` runs `nix flake check` on pull requests and pushes.

The tools these call are flake apps, tested by `nix flake check`:
`release-info`, `release-assets`, `prune-releases` and `bump-stable`.

## The index

The index lives on the `gh-pages` branch;
`build.yml` writes it with cloud-image-index's own generator, at the
commit `INDEX_REV` names.
