{
  pkgs,
  lib,
  config,
  inputs,
  ...
}: let
  firefoxPackage = pkgs.firefox-esr.overrideAttrs (old: {
    desktopItem = old.desktopItem.override {
      name = "firefox";
      desktopName = "Firefox";
      exec = "firefox-esr --name firefox %U";
      icon = "firefox";
      startupWMClass = "firefox";
    };
  });
in {
  options.modules.firefox.enable = lib.mkEnableOption "Firefox";

  config = lib.mkIf config.modules.firefox.enable {
    home.sessionVariables = {
      MOZ_GTK_TITLEBAR_DECORATION = "server";
    };

    programs.firefox = {
      enable = true;
      package = firefoxPackage;

      policies = {
        DisableAppUpdate = false;
        DontCheckDefaultBrowser = true;
      };

      profiles.default = {
        extensions.packages = with inputs.nur.legacyPackages.${pkgs.stdenv.hostPlatform.system}.repos.natsukium.my-firefox-addons; [
          adguard-adblocker
          (pkgs.fetchFirefoxAddon {
            name = "plasma-browser-integration";
            url = "https://addons.mozilla.org/firefox/downloads/latest/plasma-integration/latest.xpi";
            hash = "sha256-Nb+jdm4JcWDnT1Jb3lTZe7upDXJdqkJbneb+9uxenUQ=";
          })
        ];

        # Custom Font Settings
        settings = {
          # STARTUP BEHAVIOR
          # 3 = Restore previous session; 1 = Home page; 0 = Blank page
          "browser.startup.page" = 3;
          "shell.checkDefaultBrowser" = false;

          "browser.tabs.drawInTitlebar" = false;
          "browser.titlebar-x11-use-system-default" = true;

          # NATIVE VERTICAL TABS & SIDEBAR
          "sidebar.revamp" = true;
          "sidebar.verticalTabs" = true;
          "browser.tabs.verticalTabs" = true;

          "font.name.sans-serif.x-western" = "Inter Nerd Font";
          "font.name.serif.x-western" = "Inter Nerd Font";
          "font.name.monospace.x-western" = "FiraCode Nerd Font";
          "font.size.variable.x-western" = 16;
          "font.minimum-size.x-western" = 12;

          "font.name.sans-serif.x-unicode" = "Inter Nerd Font";
          "font.name.monospace.x-unicode" = "FiraCode Nerd Font";

          "browser.display.use_document_fonts" = 0;

          # UI Optimization
          "browser.uidensity" = 1; # Compact mode
          "toolkit.legacyUserProfileCustomizations.stylesheets" = true; # Enables userChrome.css
        };
      };
    };
  };
}
