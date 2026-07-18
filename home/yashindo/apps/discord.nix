{
  pkgs,
  pkgsUnstable,
  lib,
  config,
  ...
}: let
  discord-gpu-picker = pkgsUnstable.writeShellScriptBin "discord-gpu-picker" ''
    discord_running() {
      ${pkgs.procps}/bin/pgrep -i -u "$( ${pkgs.coreutils}/bin/id -u)" -f '(^|/)(discord)( |$)' >/dev/null
    }

    if discord_running; then
      ${lib.getExe pkgs.kdePackages.kdialog} \
        --title "Discord is already running" \
        --msgbox "Fully quit Discord before launching it on a different GPU."
      exit 0
    fi

    choice="$( ${lib.getExe pkgs.kdePackages.kdialog} \
      --title "Launch Discord" \
      --menu "Choose the GPU Discord should use:" \
      amd "AMD integrated GPU" \
      nvidia "NVIDIA dedicated GPU")" || exit 0

    # Another launcher may have started Discord while the picker was open.
    if discord_running; then
      ${lib.getExe pkgs.kdePackages.kdialog} \
        --title "Discord is already running" \
        --msgbox "Fully quit Discord before launching it on a different GPU."
      exit 0
    fi

    case "$choice" in
      amd)
        exec ${lib.getExe pkgsUnstable.discord} "$@"
        ;;
      nvidia)
        exec nvidia-offload ${lib.getExe pkgsUnstable.discord} --ozone-platform=x11 "$@"
        ;;
    esac
  '';

  discord-login-prompt = pkgs.writeShellScriptBin "discord-login-prompt" ''
    if ${lib.getExe pkgs.kdePackages.kdialog} \
      --title "Start Discord?" \
      --yesno "Would you like Discord to run in the background now?"; then
      exec nvidia-offload ${lib.getExe pkgsUnstable.discord} --ozone-platform=x11 --start-minimized
    fi
  '';
in {
  options.modules.discord.enable = lib.mkEnableOption "Discord";

  config = lib.mkIf config.modules.discord.enable {
    home.packages = [
      pkgsUnstable.discord
      pkgs.kdePackages.kdialog
      discord-gpu-picker
      discord-login-prompt
    ];

    # Skip update check and start minimized
    home.file.".config/discord/settings.json".text = builtins.toJSON {
      SKIP_HOST_UPDATE = true;
    };

    home.file.".local/share/applications/discord.desktop".text = ''
      [Desktop Entry]
      Name=Discord
      Exec=${lib.getExe discord-gpu-picker} %U
      Icon=discord
      Type=Application
      Categories=Network;InstantMessaging;
    '';

    # Ask after login whether Discord should start minimized on the dedicated GPU.
    xdg.configFile."autostart/discord.desktop".text = ''
      [Desktop Entry]
      Name=Discord
      Exec=${lib.getExe discord-login-prompt}
      Type=Application
      Categories=Network;InstantMessaging;
      X-GNOME-Autostart-enabled=true
    '';
  };
}
