{
  lib,
  config,
  pkgs,
  ...
}: let
  ghSecretFile = ../../../secrets/gh.yaml;
  hasGhSecretFile = builtins.pathExists ghSecretFile;
  tokenPath = "${config.home.homeDirectory}/.config/gh/token";
in {
  options.modules.gh.enable = lib.mkEnableOption "GitHub CLI";

  config = lib.mkIf config.modules.gh.enable (lib.mkMerge [
    {
      programs.gh = {
        enable = true;
        settings = {
          git_protocol = "https";
          prompt = "enabled";
        };
      };
    }

    (lib.mkIf hasGhSecretFile {
      sops.age.keyFile = "${config.home.homeDirectory}/.config/sops/age/keys.txt";

      sops.secrets.gh_token = {
        sopsFile = ghSecretFile;
        key = "token";
        path = tokenPath;
        mode = "0600";
      };

      # sops-nix decrypts via the user systemd service asynchronously, so poll
      # briefly for the token file before consuming it. Idempotent: gh auth
      # login is safe to re-run; it overwrites the stored credential.
      home.activation.ghAuth = lib.hm.dag.entryAfter [ "linkGeneration" ] ''
        TOKEN_FILE="${tokenPath}"
        for _ in $(seq 1 20); do
          if [[ -s "$TOKEN_FILE" ]]; then break; fi
          sleep 0.5
        done
        if [[ -s "$TOKEN_FILE" ]]; then
          ${pkgs.gh}/bin/gh auth login --with-token < "$TOKEN_FILE"
        else
          echo "gh: SOPS token not yet available at activation; run 'gh auth login' manually or re-run the rebuild workflow."
        fi
      '';
    })
  ]);
}
