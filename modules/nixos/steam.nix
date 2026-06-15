# modules/nixos/steam.nix
{
  pkgs,
  lib,
  config,
  ...
}: {
  options.modules.steam.enable =
    lib.mkEnableOption "Steam gaming support";

  config = lib.mkIf config.modules.steam.enable {
    programs.steam = {
      enable = true;

      remotePlay.openFirewall = true;
      dedicatedServer.openFirewall = true;
      localNetworkGameTransfers.openFirewall = true;

      extraCompatPackages = with pkgs; [
        proton-ge-bin
      ];
    };

    hardware.graphics = {
      enable = true;
      enable32Bit = true;
    };

    hardware.steam-hardware.enable = true;

    programs.gamemode.enable = true;

    environment.systemPackages = with pkgs; [
      gamescope
      mangohud
      protonup-qt
    ];
  };
}
