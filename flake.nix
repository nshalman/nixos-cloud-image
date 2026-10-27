{
  description = "NixOS images for SmartOS bhyve guests, configured by cloud-init's NoCloud datasource";

  # nixpkgs is the current stable release; check-stable says when a newer
  # one has been released.
  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";
  inputs.nixpkgs-unstable.url = "github:NixOS/nixpkgs/nixos-unstable";

  outputs =
    {
      self,
      nixpkgs,
      nixpkgs-unstable,
    }:
    let
      system = "x86_64-linux";
      pkgs = nixpkgs.legacyPackages.${system};
      imageSystem =
        nixpkgs:
        nixpkgs.lib.nixosSystem {
          modules = [
            self.nixosModules.smartos-guest
            ./image.nix
          ];
        };
      check-stable = pkgs.writeShellApplication {
        name = "check-stable";
        runtimeInputs = with pkgs; [
          coreutils
          git
          gnugrep
          gnused
          jq
        ];
        text = builtins.readFile ./scripts/check-stable.sh;
      };
    in
    {
      nixosModules.smartos-guest = ./smartos-guest.nix;

      nixosConfigurations.stable = imageSystem nixpkgs;
      nixosConfigurations.unstable = imageSystem nixpkgs-unstable;

      packages.${system} = {
        stable = self.nixosConfigurations.stable.config.system.build.images.qemu-efi;
        unstable = self.nixosConfigurations.unstable.config.system.build.images.qemu-efi;
        default = self.packages.${system}.stable;
      };

      checks.${system}.check-stable =
        pkgs.runCommand "check-stable-test" { nativeBuildInputs = [ check-stable ]; }
          ''
            bash ${./tests/check-stable-test.sh}
            touch $out
          '';

      apps.${system} = {
        check-stable = {
          type = "app";
          program = pkgs.lib.getExe check-stable;
        };

        boot-test = {
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
    };
}
