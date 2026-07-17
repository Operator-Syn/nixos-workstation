{
  pkgs,
  lib,
  config,
  ...
}: let
  plasmaBrowserIntegrationHost = "${pkgs.kdePackages.plasma-browser-integration}/etc/chromium/native-messaging-hosts/org.kde.plasma.browser_integration.json";

  brave-gpu-picker = pkgs.writeShellScriptBin "brave-gpu-picker" ''
    brave_running() {
      ${pkgs.procps}/bin/pgrep -u "$( ${pkgs.coreutils}/bin/id -u)" -f '(^|/)(brave|brave-browser|\.brave-wrapped)( |$)' >/dev/null
    }

    if brave_running; then
      # Brave forwards this request to its existing process, preserving the GPU
      # mode selected by the first launch.
      exec ${pkgs.brave}/bin/brave "$@"
    fi

    choice="$( ${lib.getExe pkgs.kdePackages.kdialog} \
      --title "Launch Brave" \
      --menu "Choose the GPU Brave should use:" \
      amd "AMD integrated GPU" \
      nvidia "NVIDIA dedicated GPU")" || exit 0

    # Another launcher may have started Brave while the picker was open.
    if brave_running; then
      exec ${pkgs.brave}/bin/brave "$@"
    fi

    case "$choice" in
      amd)
        exec ${pkgs.brave}/bin/brave "$@"
        ;;
      nvidia)
        exec nvidia-offload ${pkgs.brave}/bin/brave --ozone-platform=x11 "$@"
        ;;
    esac
  '';

  # This should point to the Brave profile directory for your work profile.
  # Your existing/main profile is usually "Default".
  # A second Brave profile is usually "Profile 1".
  braveWorkProfile = "Profile 1";
in {
  options.modules.brave.enable = lib.mkEnableOption "Brave Browser";

  config = lib.mkIf config.modules.brave.enable {
    home.packages = [
      pkgs.brave
      pkgs.kdePackages.kdialog
      brave-gpu-picker
    ];

    home.file.".config/BraveSoftware/Brave-Browser/NativeMessagingHosts/org.kde.plasma.browser_integration.json".source =
      plasmaBrowserIntegrationHost;

    home.sessionVariables = {
      BROWSER = lib.getExe brave-gpu-picker;
    };

    home.file.".local/share/applications/brave-browser.desktop".text = ''
      [Desktop Entry]
      Name=Brave
      GenericName=Web Browser
      Exec=${lib.getExe brave-gpu-picker} %U
      Icon=brave-browser
      Type=Application
      Categories=Network;WebBrowser;
      MimeType=text/html;x-scheme-handler/http;x-scheme-handler/https;
      StartupNotify=true
    '';

    home.file.".local/share/applications/brave-work.desktop".text = ''
      [Desktop Entry]
      Name=Brave Work
      GenericName=Web Browser
      Comment=Open Brave with the Work profile
      Exec=${lib.getExe brave-gpu-picker} --profile-directory="${braveWorkProfile}" %U
      Icon=brave-browser
      Type=Application
      Categories=Network;WebBrowser;
      MimeType=text/html;x-scheme-handler/http;x-scheme-handler/https;
      StartupNotify=true
    '';

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
