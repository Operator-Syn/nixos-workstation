{
  lib,
  config,
  ...
}: let
  sshSecretFile = ../../../secrets/ssh.yaml;
  hasSshSecretFile = builtins.pathExists sshSecretFile;
in {
  options.modules.ssh.enable = lib.mkEnableOption "SSH configuration";

  config = lib.mkIf config.modules.ssh.enable (lib.mkMerge [
    {
      programs.ssh = {
        enable = true;
        enableDefaultConfig = false;

        matchBlocks = {
          node1 = {
            hostname = "node1.internal.netbird-network";
            user = "yashindo";
            port = 2016;
            identityFile = "${config.home.homeDirectory}/.ssh/id_ed25519";
            identitiesOnly = true;

            extraOptions = {
              PreferredAuthentications = "publickey";
              PasswordAuthentication = "no";
            };
          };

          node1-public = {
            hostname = "51.79.251.21";
            user = "yashindo";
            port = 2016;
            identityFile = "${config.home.homeDirectory}/.ssh/id_ed25519";
            identitiesOnly = true;

            extraOptions = {
              PreferredAuthentications = "publickey";
              PasswordAuthentication = "no";
            };
          };

          node1-gil = {
            hostname = "node1.internal.netbird-network";
            user = "gil";
            port = 2016;
            identityFile = "${config.home.homeDirectory}/.ssh/id_ed25519";
            identitiesOnly = true;

            extraOptions = {
              PreferredAuthentications = "publickey";
              PasswordAuthentication = "no";
            };
          };

          "*" = {
            addKeysToAgent = "yes";
            compression = true;
            identityFile = "${config.home.homeDirectory}/.ssh/id_ed25519";
            identitiesOnly = false;
            serverAliveInterval = 60;
            serverAliveCountMax = 3;
          };
        };
      };
    }

    (lib.mkIf hasSshSecretFile {
      sops.age.keyFile = "${config.home.homeDirectory}/.config/sops/age/keys.txt";

      sops.secrets.ssh_id_ed25519 = {
        sopsFile = sshSecretFile;
        key = "data";
        path = "${config.home.homeDirectory}/.ssh/id_ed25519";
        mode = "0600";
      };
    })
  ]);
}