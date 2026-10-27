{
  description = "NixOS images for SmartOS bhyve guests, configured by cloud-init's NoCloud datasource";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";

  outputs =
    { self, nixpkgs }:
    let
      system = "x86_64-linux";
      pkgs = nixpkgs.legacyPackages.${system};
    in
    {
      nixosModules.smartos-guest = ./smartos-guest.nix;

      nixosConfigurations.smartos = nixpkgs.lib.nixosSystem {
        modules = [
          self.nixosModules.smartos-guest
          {
            nixpkgs.hostPlatform = system;
            system.stateVersion = "26.05";

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
                  import "${nixpkgs}/nixos/lib/make-disk-image.nix" {
                    inherit lib config pkgs;
                    inherit (config.virtualisation) diskSize;
                    inherit (config.image) baseName;
                    format = "qcow2-compressed";
                    partitionTableType = "efi";
                  }
                );
              };
          }
        ];
      };

      packages.${system}.default = self.nixosConfigurations.smartos.config.system.build.images.qemu-efi;

      apps.${system}.boot-test = {
        type = "app";
        program = pkgs.lib.getExe (
          pkgs.writeShellApplication {
            name = "boot-test";
            runtimeInputs = with pkgs; [
              coreutils
              dosfstools
              findutils
              gnugrep
              gnused
              jq
              mtools
              openssh
              qemu_kvm
            ];
            runtimeEnv = {
              OVMF_CODE = "${pkgs.OVMF.fd}/FV/OVMF_CODE.fd";
              OVMF_VARS = "${pkgs.OVMF.fd}/FV/OVMF_VARS.fd";
              CIDATA = ./tests/cidata;
              DEFAULT_IMAGE = self.packages.${system}.default;
            };
            text = builtins.readFile ./tests/boot-test.sh;
          }
        );
      };
    };
}
