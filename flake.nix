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
      # What booting from the image's disk needs from a configuration.
      bootLayout =
        config:
        builtins.toJSON {
          fileSystems = builtins.mapAttrs (_: fs: {
            inherit (fs)
              device
              fsType
              autoResize
              options
              ;
          }) config.fileSystems;
          systemd-boot = config.boot.loader.systemd-boot.enable;
          grub = config.boot.loader.grub.enable;
          canTouchEfiVariables = config.boot.loader.efi.canTouchEfiVariables;
          growPartition = config.boot.growPartition;
        };
      # A guest that nixos-rebuilds from nixosConfigurations.<channel> must
      # keep the image's filesystems and bootloader.
      guestMatchesImage =
        channel:
        let
          guest = self.nixosConfigurations.${channel}.config;
          image = guest.system.build.images.qemu-efi.passthru.config;
        in
        pkgs.runCommand "guest-matches-image-${channel}" { } ''
          diff -u ${pkgs.writeText "image.json" (bootLayout image)} \
            ${pkgs.writeText "guest.json" (bootLayout guest)}
          touch $out
        '';
      # A tool from scripts/<name>.sh.
      script =
        name: runtimeInputs:
        pkgs.writeShellApplication {
          inherit name runtimeInputs;
          text = builtins.readFile ./scripts/${name}.sh;
        };
      check-stable = script "check-stable" (
        with pkgs;
        [
          coreutils
          git
          gnugrep
          gnused
          jq
        ]
      );
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

      checks.${system} = {
        check-stable =
          pkgs.runCommand "check-stable-test" { nativeBuildInputs = [ check-stable ]; }
            ''
              bash ${./tests/check-stable-test.sh}
              touch $out
            '';
        guest-matches-image-stable = guestMatchesImage "stable";
        guest-matches-image-unstable = guestMatchesImage "unstable";
      };

      apps.${system} = {
        check-stable = {
          type = "app";
          program = pkgs.lib.getExe check-stable;
          meta.description = "Say whether the stable input follows the newest NixOS release";
        };

        boot-test = {
          type = "app";
          meta.description = "Boot an image as SmartOS would and check cloud-init configured it";
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
              };
              text = builtins.readFile ./tests/boot-test.sh;
            }
          );
        };
      };
    };
}
