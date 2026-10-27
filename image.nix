# The published image: the SmartOS guest as nixpkgs' qemu-efi image,
# for whichever nixpkgs evaluates it.
{ lib, modulesPath, ... }:
{
  nixpkgs.hostPlatform = "x86_64-linux";
  system.stateVersion = lib.trivial.release;

  # Compress the download (2.4 GB to about 0.7 GB). The qemu-efi
  # module offers only raw or qcow2, so build it as it does, but
  # with make-disk-image's qcow2-compressed, which is zlib.
  image.modules.qemu-efi =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    {
      system.build.image = lib.mkForce (
        import (modulesPath + "/../lib/make-disk-image.nix") {
          inherit lib config pkgs;
          inherit (config.virtualisation) diskSize;
          inherit (config.image) baseName;
          format = "qcow2-compressed";
          partitionTableType = "efi";
        }
      );
    };
}
