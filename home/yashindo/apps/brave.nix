{
  pkgs,
  lib,
  config,
  ...
}: {
  options.modules.brave.enable = lib.mkEnableOption "Brave Browser";

  config = lib.mkIf config.modules.brave.enable {
    home.file.".config/BraveSoftware/Brave-Browser/NativeMessagingHosts/org.kde.plasma.browser_integration.json".source = "${pkgs.kdePackages.plasma-browser-integration}/etc/chromium/native-messaging-hosts/org.kde.plasma.browser_integration.json";
    home.packages = [pkgs.brave];

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
