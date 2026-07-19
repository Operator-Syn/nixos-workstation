{
  config,
  lib,
  ...
}: let
  cfg = config.modules.hermes.graphify;
  vaultPath = "/srv/obsidian/hermes-vault";
in {
  options.modules.hermes.graphify = {
    enable = lib.mkEnableOption "Graphify MCP integration for Hermes";
    port = lib.mkOption {
      type = lib.types.port;
      default = 9292;
      description = "Graphify MCP loopback port used by Hermes.";
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = config.modules.hermes.enable;
        message = "modules.hermes.graphify.enable requires modules.hermes.enable.";
      }
      {
        assertion = config.modules.graphify.enable;
        message = "modules.hermes.graphify.enable requires modules.graphify.enable.";
      }
      {
        assertion = cfg.port == config.modules.graphify.port;
        message = "Hermes and Graphify MCP ports must match.";
      }
    ];

    systemd.services.hermes-desktop-backend = {
      environment.OBSIDIAN_VAULT_PATH = vaultPath;
      serviceConfig.ReadWritePaths = [vaultPath];
    };
  };
}
