{
  pkgs,
  lib,
  config,
  ...
}: let
  gstPlugins = with pkgs.gst_all_1; [
    gstreamer
    gst-plugins-bad
    gst-plugins-base
    gst-plugins-good
    gst-plugins-ugly
  ];

  castersoundboard = pkgs.stdenv.mkDerivation {
    pname = "castersoundboard";
    version = "unstable-2020-08-21";

    src = pkgs.fetchFromGitHub {
      owner = "JupiterBroadcasting";
      repo = "CasterSoundboard";
      rev = "master";
      hash = "sha256-YXM3QzOJxJZJ+tjbaXE0jWVhF9VshM1hRBsSMHhn8to=";
    };

    sourceRoot = "source/CasterSoundboard";

    nativeBuildInputs = with pkgs.qt5; [
      qmake
      wrapQtAppsHook
    ];

    buildInputs = gstPlugins ++ [pkgs.qt5.qtmultimedia];

    qmakeFlags = [
      "PREFIX=${placeholder "out"}"
    ];

    qtWrapperArgs = [
      "--prefix GST_PLUGIN_SYSTEM_PATH_1_0 : ${lib.makeSearchPath "lib/gstreamer-1.0" (map lib.getLib gstPlugins)}"
    ];

    meta = {
      description = "A soundboard for hot-keying and playing back sounds";
      homepage = "https://github.com/JupiterBroadcasting/CasterSoundboard";
      license = lib.licenses.lgpl3Only;
      platforms = lib.platforms.linux;
      mainProgram = "CasterSoundboard";
    };
  };
in {
  options.modules.castersoundboard.enable = lib.mkEnableOption "CasterSoundBoard";

  config = lib.mkIf config.modules.castersoundboard.enable {
    home.packages = [
      castersoundboard
    ];
  };
}
