{pkgs}: let
  lib = pkgs.lib;

  nativeLibraries = with pkgs; [
    alsa-lib
    atk
    cups
    dbus
    expat
    glib
    libdrm
    libffi
    libxcb
    libxkbcommon
    libxml2
    libxslt
    mesa
    nspr
    nss
    openssl
    readline
    sqlite
    stdenv.cc.cc.lib
    zlib
  ];

  pythonPackages = with pkgs; [
    gcc
    git
    gnumake
    pipenv
    pkg-config
    python314
  ];

  nodePackages = with pkgs; [
    bun
    nodejs_24
    pnpm
  ];

  playwrightEnv = {
    PLAYWRIGHT_BROWSERS_PATH = "${pkgs.playwright-driver.browsers}";
    PLAYWRIGHT_SKIP_BROWSER_DOWNLOAD = "1";
  };

  mkPythonShell = extraPackages: extraAttrs:
    pkgs.mkShell (extraAttrs
      // {
        packages = pythonPackages ++ extraPackages;

        LD_LIBRARY_PATH = lib.makeLibraryPath nativeLibraries;
        PIPENV_VENV_IN_PROJECT = "1";
      });
in {
  default = pkgs.mkShell {
    packages = with pkgs; [
      alejandra
      git
      nil
      nixfmt-rfc-style
      pkg-config
      tree
    ];
  };

  python = mkPythonShell [] {};

  node = pkgs.mkShell {
    packages = nodePackages;
  };

  python-node = mkPythonShell nodePackages {};

  playwright = pkgs.mkShell ({
      packages = with pkgs; [
        playwright-driver.browsers
      ];
    }
    // playwrightEnv);

  python-playwright =
    mkPythonShell [
      pkgs.playwright-driver.browsers
    ]
    playwrightEnv;

  cuda = mkPythonShell (with pkgs; [
    cudaPackages.cudatoolkit
    openmpi
  ]) {};

  latex = pkgs.mkShell {
    packages = with pkgs; [
      texlive.combined.scheme-full
    ];
  };
}
