# cloud-image-nix

A NixOS image for SmartOS bhyve guests, configured at boot by cloud-init
from the NoCloud `CIDATA` disk that `vmadm` attaches: hostname from
`meta-data`, users and SSH keys from `user-data`, addresses, routes and
resolvers from `network-config`.

The image is nixpkgs' `qemu-efi` image (UEFI, systemd-boot, ext4 root
that grows to fill the disk) plus `smartos-guest.nix`, which turns on
cloud-init and puts the console on the serial port `vmadm console` uses.

## Build

    nix build

`result/` then holds the qcow2 image.

## Test

    nix run .#boot-test [IMAGE]

Boots the image (by default the flake's) under QEMU with OVMF the way
SmartOS boots a bhyve guest: UEFI with no saved boot entries, virtio disk
and NIC, and a 16 MiB FAT16 `CIDATA` disk holding `tests/cidata`, which
is in the format smartos-live's `nocloud.js` writes. It checks over SSH
that cloud-init applied all of it, reboots, and checks again. Needs KVM.

## Using the module in your own configuration

`nixosModules.smartos-guest` is the module on its own, to add to a
configuration of your own and build its `system.build.images.qemu-efi`.
