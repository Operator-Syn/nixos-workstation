{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.modules.obsidian;
  vaultPath = "/srv/obsidian/hermes-vault";
  obsidian-hermes-vault = pkgs.writeShellScriptBin "obsidian-hermes-vault" ''
    set -eu

    vault=${lib.escapeShellArg vaultPath}
    if ! test -d "$vault"; then
      echo "Hermes Obsidian vault is unavailable: $vault" >&2
      echo "Activate modules.obsidianHermesVault and rebuild the system first." >&2
      exit 1
    fi

    exec ${pkgs.obsidian}/bin/obsidian "$vault" "$@"
  '';
in {
  options.modules.obsidian.enable = lib.mkEnableOption "Obsidian for the Hermes vault";

  config = lib.mkIf cfg.enable {
    home.packages = [
      pkgs.obsidian
      obsidian-hermes-vault
    ];

    home.file.".local/share/applications/obsidian-hermes-vault.desktop".text = ''
      [Desktop Entry]
      Name=Hermes Obsidian Vault
      Comment=Open the shared Hermes Obsidian vault
      Exec=${obsidian-hermes-vault}/bin/obsidian-hermes-vault %U
      TryExec=${obsidian-hermes-vault}/bin/obsidian-hermes-vault
      Icon=obsidian
      Terminal=false
      Type=Application
      Categories=Office;Utility;
      StartupWMClass=obsidian
    '';
  };
}
