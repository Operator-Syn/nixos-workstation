{
  pkgs,
  lib,
  config,
  ...
}: let
  plasmaBrowserIntegrationHost = "${pkgs.kdePackages.plasma-browser-integration}/etc/chromium/native-messaging-hosts/org.kde.plasma.browser_integration.json";
in {
  options.modules.brave.enable = lib.mkEnableOption "Brave Browser";

  config = lib.mkIf config.modules.brave.enable {
    home.packages = [
      pkgs.brave
      # Keep a second Chromium implementation available for browser tooling
      # when Brave-specific startup or profile state is unsuitable.
      pkgs.google-chrome
    ];

    home.file.".config/BraveSoftware/Brave-Browser/NativeMessagingHosts/org.kde.plasma.browser_integration.json".source =
      plasmaBrowserIntegrationHost;

    home.sessionVariables = {
      BROWSER = "brave";
    };

    xdg.mimeApps = {
      enable = true;
      defaultApplications = {
        "text/html" = ["brave-browser.desktop"];
        "x-scheme-handler/http" = ["brave-browser.desktop"];
        "x-scheme-handler/https" = ["brave-browser.desktop"];
      };
    };
  };
}
