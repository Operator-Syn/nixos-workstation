{
  bedrockSource,
  bash,
  coreutils,
  curl,
  findutils,
  gawk,
  gnugrep,
  gnused,
  gnutar,
  lib,
  makeWrapper,
  libxcomposite,
  python312,
  stdenvNoCC,
  steam,
  zstd,
}: let
  python = python312.withPackages (ps:
    with ps; [
      certifi
      cryptography
      packaging
      pyside6
      python-xlib
    ]);
  unwrapped = stdenvNoCC.mkDerivation {
    pname = "bedrock-on-linux";
    version = "2.2.4";
    src = bedrockSource;

    dontConfigure = true;
    dontBuild = true;
    doCheck = true;

    nativeBuildInputs = [makeWrapper];

    patches = [
      ./patches/0001-device-login-ux.patch
      ./patches/0002-nixos-runtime-and-doctor.patch
    ];

    checkPhase = ''
      runHook preCheck

      PYTHONPATH="$PWD" ${python}/bin/python3 - <<'PY'
      from PySide6.QtCore import QObject
      from PySide6.QtWidgets import QApplication

      # Importing QtCore and QtWidgets validates the packaged GUI toolkit
      # without opening a display during the Nix build.
      assert QObject is not None
      assert QApplication is not None
      print("BedrockOnLinux Qt GUI dependencies are available")
      PY

      PYTHONPATH="$PWD" ${python}/bin/python3 - <<'PY'
      from bol.prefix import headless_setup_env

      result = headless_setup_env({
          "DISPLAY": ":0",
          "LD_LIBRARY_PATH": "/nix/store/inherited-libraries",
          "STEAM_RUNTIME_LIBRARY_PATH": "/nix/store/inherited-runtime",
          "WAYLAND_DISPLAY": "wayland-0",
          "XAUTHORITY": "/tmp/xauth",
      })
      assert "LD_LIBRARY_PATH" not in result
      assert "STEAM_RUNTIME_LIBRARY_PATH" not in result
      assert "DISPLAY" not in result
      assert "WAYLAND_DISPLAY" not in result
      assert "XAUTHORITY" not in result
      print("Headless Wine setup environment is isolated from host graphics libraries")
      PY

      runHook postCheck
    '';

    installPhase = ''
      runHook preInstall

      install -d \
        "$out/lib/bedrock-on-linux" \
        "$out/share/applications" \
        "$out/share/icons/hicolor/256x256/apps"

      cp -r bol "$out/lib/bedrock-on-linux/"
      install -Dm755 bedrock-on-linux \
        "$out/lib/bedrock-on-linux/bedrock-on-linux"
      install -Dm644 data/bedrock-on-linux.desktop \
        "$out/share/applications/bedrock-on-linux.desktop"
      install -Dm644 data/icon.png \
        "$out/share/icons/hicolor/256x256/apps/bedrock-on-linux.png"
      install -Dm644 LICENSE \
        "$out/share/licenses/bedrock-on-linux/LICENSE"

      makeWrapper ${python}/bin/python3 "$out/bin/bedrock-on-linux" \
        --add-flags "$out/lib/bedrock-on-linux/bedrock-on-linux" \
        --prefix PATH : "${lib.makeBinPath [bash coreutils curl findutils gawk gnugrep gnused gnutar zstd]}" \
        --prefix PYTHONPATH : "$out/lib/bedrock-on-linux" \
        --set QT_QPA_PLATFORM xcb \
        --unset LD_LIBRARY_PATH \
        --unset STEAM_RUNTIME_LIBRARY_PATH \
        --set PYTHONNOUSERSITE 1

      runHook postInstall
    '';

    meta = {
      description = "Run Minecraft Bedrock for Windows on Linux";
      homepage = "https://github.com/Wyze3306/BedrockOnLinux";
      license = lib.licenses.mit;
      mainProgram = "bedrock-on-linux";
      platforms = ["x86_64-linux"];
    };
  };
in
  steam.buildRuntimeEnv {
    pname = "bedrock-on-linux";
    version = "2.2.4";
    executableName = "bedrock-on-linux";
    runScript = lib.getExe unwrapped;
    extraPkgs = _: [libxcomposite unwrapped];

    # Keep the desktop entry and icon from the Nix-built launcher visible in
    # the FHS wrapper's output, just like the official umu-launcher package.
    extraInstallCommands = ''
      ln -s ${unwrapped}/share $out/share
    '';

    meta = {
      description = "Run Minecraft Bedrock for Windows on Linux";
      homepage = "https://github.com/Wyze3306/BedrockOnLinux";
      license = lib.licenses.mit;
      mainProgram = "bedrock-on-linux";
      platforms = ["x86_64-linux"];
    };
  }
