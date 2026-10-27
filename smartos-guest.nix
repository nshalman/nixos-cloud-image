# A NixOS guest for SmartOS bhyve, configured at boot by cloud-init from
# the NoCloud CIDATA disk vmadm attaches: hostname from meta-data, users
# and SSH keys from user-data, and addresses from network-config.
{
  lib,
  modulesPath,
  pkgs,
  ...
}:
{
  imports = [ (modulesPath + "/profiles/qemu-guest.nix") ];

  # The disk as nixpkgs' qemu-efi image lays it out, so that a guest can
  # nixos-rebuild from a configuration made with this module.
  fileSystems."/" = {
    device = "/dev/disk/by-label/nixos";
    fsType = "ext4";
    autoResize = true;
  };
  fileSystems."/boot" = {
    device = "/dev/disk/by-label/ESP";
    fsType = "vfat";
  };
  boot.loader.systemd-boot.enable = true;
  boot.growPartition = true;

  # vmadm console attaches to the guest's first serial port; the last
  # console= becomes /dev/console.
  boot.kernelParams = [
    "console=tty0"
    "console=ttyS0,115200"
  ];

  services.cloud-init = {
    enable = true;
    network.enable = true;
    # SmartOS only offers NoCloud; probing the network datasources (EC2,
    # OpenStack, ...) would only add timeouts to every boot.
    settings.datasource_list = [
      "NoCloud"
      "None"
    ];
    # nixpkgs' cloud-init 25.2 installs write-ssh-key-fingerprints in
    # libexec/ rather than libexec/cloud-init/, where keys-to-console looks
    # for it, so the module only warns and degrades cloud-init's status.
    # Fixed on nixos-unstable by NixOS/nixpkgs@3f5843fff5; drop this once
    # the stable channel has that fix too.
    settings.ssh.emit_keys_to_console = false;
    # The image has no SSH host keys, and NixOS's sshd-keygen makes them on
    # first boot. Left to it, cloud-init's ssh module would delete and
    # regenerate them at the same time, since cloud-config is not ordered
    # against sshd-keygen, and fail with "already exists".
    settings.ssh_deletekeys = false;
    settings.ssh_genkeytypes = [ ];
  };
  # The module runs cloud-init from its units only; put it on the PATH
  # too, for `cloud-init status --wait` and friends.
  environment.systemPackages = [ pkgs.cloud-init ];

  # The network and hostname come from cloud-init.
  networking.useDHCP = false;
  networking.hostName = lib.mkDefault "";

  services.openssh.enable = true;

  nix.settings.experimental-features = [
    "nix-command"
    "flakes"
  ];
}
