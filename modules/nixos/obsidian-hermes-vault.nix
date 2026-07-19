{
  config,
  lib,
  ...
}: let
  cfg = config.modules.obsidianHermesVault;
in {
  options.modules.obsidianHermesVault.enable = lib.mkEnableOption "shared Hermes and Obsidian vault";

  config = lib.mkIf cfg.enable {
    users.groups."obsidian-hermes" = {};
    users.users.feilhann.extraGroups = ["obsidian-hermes"];
    users.users.yashindo.extraGroups = ["obsidian-hermes"];

    systemd.tmpfiles.rules = [
      "d /srv/obsidian 0750 root obsidian-hermes - -"
      "d /srv/obsidian/hermes-vault 2770 yashindo obsidian-hermes - -"
      "d /var/lib/graphify 0750 yashindo obsidian-hermes - -"
      "d /var/lib/graphify/hermes-vault 0750 yashindo obsidian-hermes - -"
      "d /var/lib/graphify/hermes-derived-vault 2770 yashindo obsidian-hermes - -"
    ];
  };
}
