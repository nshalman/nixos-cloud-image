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
NixOS release's channel (the `nixpkgs` input, `nixos-26.05`), and
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

`nixosModules.smartos-guest` is the module on its own, to add to a
configuration of your own and build its `system.build.images.qemu-efi`.
