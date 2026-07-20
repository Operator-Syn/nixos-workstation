# modules/nixos/steam.nix
{
  pkgs,
  pkgsUnstable,
  lib,
  config,
  ...
}: {
  imports = [
    ./steam/protontricks.nix
  ];

  options.modules.steam.enable =
    lib.mkEnableOption "Steam gaming support";

  config = lib.mkIf config.modules.steam.enable {
    modules.steam.protontricks.enable = lib.mkDefault true;

    programs.anime-game-launcher.enable = true;
    programs.honkers-railway-launcher.enable = true;

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
      lutris
      mangohud
      protonup-qt
      wineWowPackages.waylandFull
      winetricks
      cabextract
      p7zip

      (writeShellScriptBin "genshin-launcher" ''
        exec nvidia-offload ${anime-game-launcher}/bin/anime-game-launcher "$@"
      '')

      (writeShellScriptBin "hsr-launcher" ''
        exec nvidia-offload ${honkers-railway-launcher}/bin/honkers-railway-launcher "$@"
      '')
    ];
  };
}
