{
  pkgs,
  lib,
  config,
  ...
}: let
  plasmaBrowserIntegrationHost = "${pkgs.kdePackages.plasma-browser-integration}/etc/chromium/native-messaging-hosts/org.kde.plasma.browser_integration.json";

  # This should point to the Brave profile directory for your work profile.
  # Your existing/main profile is usually "Default".
  # A second Brave profile is usually "Profile 1".
  braveWorkProfile = "Profile 1";
in {
  options.modules.brave.enable = lib.mkEnableOption "Brave Browser";

  config = lib.mkIf config.modules.brave.enable {
    home.packages = [pkgs.brave];

    home.file.".config/BraveSoftware/Brave-Browser/NativeMessagingHosts/org.kde.plasma.browser_integration.json".source =
      plasmaBrowserIntegrationHost;

    home.sessionVariables = {
      BROWSER = "brave";
    };

    xdg.desktopEntries.brave-work = {
      name = "Brave Work";
      genericName = "Web Browser";
      comment = "Open Brave with the Work profile";
      exec = "${pkgs.brave}/bin/brave --profile-directory=\"${braveWorkProfile}\" %U";
      icon = "brave-browser";
      terminal = false;
      categories = ["Network" "WebBrowser"];
      mimeType = [
        "text/html"
        "x-scheme-handler/http"
        "x-scheme-handler/https"
      ];
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
