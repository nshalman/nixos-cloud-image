# cloud-image-nix

A NixOS image for SmartOS bhyve guests, configured at boot by cloud-init
from the NoCloud `CIDATA` disk that `vmadm` attaches: hostname from
`meta-data`, users and SSH keys from `user-data`, addresses, routes and
resolvers from `network-config`.

The image is nixpkgs' `qemu-efi` image (UEFI, systemd-boot, ext4 root
that grows to fill the disk) plus `smartos-guest.nix`, which turns on
cloud-init and puts the console on the serial port `vmadm console` uses.

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

## Using the module in your own configuration

`nixosModules.smartos-guest` is the module on its own. It sets the
image's filesystems and bootloader, so a configuration built on it can
both build an image (`system.build.images.qemu-efi`) and be applied with
`nixos-rebuild` inside a guest booted from one. What cloud-init sets up
(hostname, network, users, SSH keys, sudo) lives in files NixOS leaves
alone, so it survives rebuilds and reboots, unless your configuration
takes that over itself (setting `networking.hostName`, or
`users.mutableUsers = false`, for example).

## Releases

GitHub Actions publish each image as a release: the qcow2 as
`nixos-smartos-x86_64.qcow2`, its `.sha256`, and `image.json`, which
records the NixOS version, nixpkgs revision, source commit and image
derivation. Unstable builds are pre-releases, so the latest release is
always the newest stable image. Tags are `<NixOS version>-<first 8
characters of the image derivation's hash>`, and point at a commit
holding the `flake.lock` the image was built from. When the build
updated the lock, that commit is on no branch.
`nix build github:nshalman/nixos-cloud-image/<tag>#<channel>` builds the
same configuration from the same nixpkgs. The image is equivalent but not
byte-identical, because the image build isn't reproducible bit for bit.

- `build.yml` builds from the head of each channel: unstable weekly,
  stable monthly and on every push to `main`. It skips images released
  already, boot-tests the rest before releasing them, and keeps the newest
  3 releases of each stable series and 4 of unstable.
- `check-stable.yml` runs daily. When NixOS tags a newer release, it opens
  a pull request moving the stable input to it, with the result of
  building and boot-testing that image.
- `ci.yml` runs `nix flake check` on pull requests and pushes.

The tools these call are flake apps, tested by `nix flake check`:
`release-info`, `release-assets`, `prune-releases` and `bump-stable`.
