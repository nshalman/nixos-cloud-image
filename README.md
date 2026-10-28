# nixos-cloud-image

A NixOS image for SmartOS bhyve guests, configured at boot by cloud-init
from the NoCloud `CIDATA` disk that `vmadm` attaches: hostname from
`meta-data`, users and SSH keys from `user-data`, addresses, routes and
resolvers from `network-config`.

The image is nixpkgs' `qemu-efi` image (UEFI, systemd-boot, ext4 root
that grows to fill the disk) plus `smartos-guest.nix`, which turns on
cloud-init and puts the console on the serial port `vmadm console` uses.

## Importing on SmartOS

[`cloud-image`](https://github.com/TritonDataCenter/cloud-image-index)
imports these images from the index this repository publishes on GitHub
Pages, in cloud-image-index's format:

    cloud-image import --index https://nshalman.github.io/nixos-cloud-image/ nixos latest

`nixos dev` imports the unstable image, and `cloud-image avail` with the
same `--index` lists both.

## Releases

GitHub Actions publish each image as a release: the qcow2 as
`nixos-smartos-x86_64.qcow2`, its `.sha256`, and `image.json`, which
records the NixOS version, nixpkgs revision, source commit and image
derivation. Unstable builds are pre-releases, so the latest release is
always the newest stable image. Tags are `<NixOS version>-<first 8
characters of the image derivation's hash>`, and point at a commit
holding the `flake.lock` the image was built from.
`nix build github:nshalman/nixos-cloud-image/<tag>#<channel>` builds the
same configuration from the same nixpkgs. The image is equivalent but not
byte-identical, because the image build isn't reproducible bit for bit.

## Using the module in your own configuration

`nixosModules.smartos-guest` is the module on its own. It sets the
image's filesystems and bootloader, so a configuration built on it can
both build an image (`system.build.images.qemu-efi`) and be applied with
`nixos-rebuild` inside a guest booted from one. What cloud-init sets up
(hostname, network, users, SSH keys, sudo) lives in files NixOS leaves
alone, so it survives rebuilds and reboots, unless your configuration
takes that over itself (setting `networking.hostName`, or
`users.mutableUsers = false`, for example).

Building, testing and the release pipeline are described in
[MAINTAINING.md](MAINTAINING.md).
