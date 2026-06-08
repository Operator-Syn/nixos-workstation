{
  pkgs,
  lib,
  config,
  ...
}: {
  options.modules.cava.enable = lib.mkEnableOption "CAVA Visualizer";

  config = lib.mkIf config.modules.cava.enable {
    home.packages = [pkgs.cava];

    xdg.configFile."cava/config".text = ''
      [general]
      # Merges L+R but prevents the 'mirrored' frequency distribution
      channels = mono
      framerate = 144
      autosens = 1
      bar_width = 3
      bar_spacing = 1

      [input]
      method = pipewire
      source = auto

      [color]
      gradient = 1
      gradient_count = 8
      gradient_color_1 = '#94e2d5'
      gradient_color_2 = '#89dceb'
      gradient_color_3 = '#74c7ec'
      gradient_color_4 = '#89b4fa'
      gradient_color_5 = '#cba6f7'
      gradient_color_6 = '#f5c2e7'
      gradient_color_7 = '#eba0ac'
      gradient_color_8 = '#f38ba8'

      [smoothing]
      # Disabling monstercat is key to stopping the center-alignment
      monstercat = 0
      waves = 0
      integral = 0
      noise_reduction = 15
      gravity = 120

      [output]
      method = ncurses
      # This ensures the output isn't trying to 'center' the bars
      alway_on_top = 0
    '';
  };
}
