{pkgs, ...}: let
  tokenFile = "/run/secrets/gh_token";
  ghWithToken = pkgs.writeShellScriptBin "gh" ''
    if [[ -s "${tokenFile}" ]]; then
      export GH_TOKEN="$(${pkgs.coreutils}/bin/cat "${tokenFile}")"
    fi
    exec ${pkgs.gh}/bin/gh "$@"
  '';
in {
  home.username = "feilhann";
  home.homeDirectory = "/home/feilhann";
  home.stateVersion = "25.11";

  programs.gh = {
    enable = true;
    package = ghWithToken;
    settings = {
      git_protocol = "https";
      prompt = "enabled";
    };
  };
}
