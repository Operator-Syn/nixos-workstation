{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.modules.easyeffects;

  # EasyEffects identifies an input device by its PipeWire node name, which comes
  # from the device itself, so a different microphone changes this identifier.
  micDevice = "alsa_input.usb-Shenzhen_Hollyland_Technology_Co._Ltd_Wireless_microphone_C6FX222T472-01.analog-stereo";
  presetName = "Wireless-Mic-Noise-Cancel";

  jsonFormat = pkgs.formats.json {};

  # Starter microphone chain and its default values. This is a starting point,
  # not a declaration: activation writes the preset only when the file is
  # missing, after which EasyEffects owns it and GUI edits survive every rebuild.
  starterPreset = {
    input = {
      blocklist = [];
      "plugins_order" = [
        "autogain#0"
        "gate#0"
        "deepfilternet#0"
        "rnnoise#0"
      ];
      "autogain#0" = {
        bypass = false;
        "input-gain" = 0.0;
        "output-gain" = 0.0;
        target = -23.0;
        "silence-threshold" = -70.0;
        "maximum-history" = 15;
        reference = "Geometric Mean (MSI)";
        "force-silence" = false;
      };
      "gate#0" = {
        bypass = false;
        "input-gain" = 0.0;
        "output-gain" = 0.0;
        dry = -80.01;
        wet = 0.0;
        attack = 20.0;
        release = 100.0;
        "curve-threshold" = -24.0;
        "curve-zone" = -6.0;
        hysteresis = false;
        "hysteresis-threshold" = -12.0;
        "hysteresis-zone" = -6.0;
        reduction = -24.0;
        makeup = 0.0;
        "stereo-split" = false;
        sidechain = {
          type = "Internal";
          mode = "Peak";
          source = "Middle";
          "stereo-split-source" = "Left/Right";
          preamp = 0.0;
          reactivity = 10.0;
          lookahead = 0.0;
        };
        "hpf-mode" = "Off";
        "hpf-frequency" = 10.0;
        "lpf-mode" = "Off";
        "lpf-frequency" = 20000.0;
        "input-to-sidechain" = -80.01;
        "input-to-link" = -80.01;
        "sidechain-to-input" = -80.01;
        "sidechain-to-link" = -80.01;
        "link-to-sidechain" = -80.01;
        "link-to-input" = -80.01;
      };
      "deepfilternet#0" = {
        bypass = false;
        "input-gain" = 0.0;
        "output-gain" = 0.0;
        "attenuation-limit" = 50.0;
        "min-processing-threshold" = -10.0;
        "max-erb-processing-threshold" = 30.0;
        "max-df-processing-threshold" = 20.0;
        "min-processing-buffer" = 0;
        "post-filter-beta" = 0.02;
      };
      "rnnoise#0" = {
        bypass = false;
        "input-gain" = 0.0;
        "output-gain" = 0.0;
        "model-name" = "";
        "enable-vad" = true;
        "vad-thres" = 70.0;
        wet = 0.0;
        release = 125.0;
        "use-standard-model" = true;
      };
    };
  };

  # No autoload profile is seeded, deliberately. An autoload profile is keyed on a
  # device and stores a literal "preset-name", so seeding one pins that device to
  # one preset and overrides whatever was picked last in the GUI. EasyEffects
  # already restores `[Presets] lastLoadedInputPreset` from
  # ~/.config/easyeffects/db/easyeffectsrc at startup, which is the behaviour to
  # keep: the last preset chosen is the one that comes back.
  # Minimal settings seed: run recording applications through the microphone
  # pipeline, and capture the wireless microphone rather than the onboard
  # device. Written only when the file is absent, because EasyEffects rewrites
  # this file continuously as preferences change in the GUI.
  starterSettings = pkgs.writeText "easyeffectsrc" ''
    [EffectsPipelines]
    processAllInputs=true
    processAllOutputs=false

    [StreamInputs]
    inputDevice=${micDevice}
    useDefaultInputDevice=false
  '';

  seeds = [
    {
      target = "${config.xdg.dataHome}/easyeffects/input/${presetName}.json";
      source = jsonFormat.generate "${presetName}.json" starterPreset;
    }
    {
      target = "${config.xdg.configHome}/easyeffects/db/easyeffectsrc";
      source = starterSettings;
    }
  ];

  # `install -m` keeps a seeded file user-writable. A plain copy would inherit
  # the Nix store's read-only mode, and EasyEffects would then fail to save it.
  seedCommand = seed: ''
    if [ ! -e ${lib.escapeShellArg seed.target} ]; then
      $DRY_RUN_CMD ${pkgs.coreutils}/bin/mkdir -p ${lib.escapeShellArg (builtins.dirOf seed.target)}
      $DRY_RUN_CMD ${pkgs.coreutils}/bin/install -m 0644 ${lib.escapeShellArg seed.source} ${lib.escapeShellArg seed.target}
    fi
  '';
in {
  options.modules.easyeffects.enable =
    lib.mkEnableOption "EasyEffects";

  config = lib.mkIf cfg.enable {
    services.easyeffects.enable = true;

    # EasyEffects aborts with a core dump when its PipeWire connection is pulled
    # away from under it ("pw_manager.cpp: No connection to PipeWire. Aborting!").
    # PipeWire restarts on every rebuild, and that abort was this unit's dominant
    # failure mode. PartOf= makes a PipeWire restart restart EasyEffects as well;
    # After= orders the stop so EasyEffects exits through its own ExecStop before
    # PipeWire goes down. Measured on Hiraeth: a PipeWire restart went from one
    # core-dump failure to a clean restart, chain and realtime scheduling intact.
    systemd.user.services.easyeffects.Unit = {
      PartOf = ["pipewire.service"];
      After = ["pipewire.service"];
    };

    # Latency-sensitive, so outrank ordinary work instead of competing with it.
    # The DSP itself runs in PipeWire's data loop, which is already SCHED_FIFO and
    # is unaffected by any nice value; this covers the process's own threads
    # (graph events, meters, settings), which ran at nice 0 while PipeWire's
    # control plane sat at -11. RLIMIT_NICE from the @pipewire login limit is 39,
    # and that is what permits -19.
    systemd.user.services.easyeffects.Service = {
      Nice = -19;
      CPUWeight = 1000;
    };

    # Do not move this starter set to services.easyeffects.extraPresets: that
    # option publishes presets through xdg.dataFile, which links them read-only
    # into the Nix store, so EasyEffects cannot save, rename or delete them from
    # the GUI. Each file here is seeded once and then owned by EasyEffects.
    home.activation.seedEasyeffectsStarterState = lib.hm.dag.entryAfter ["writeBoundary"] ''
      ${lib.concatMapStrings seedCommand seeds}
    '';
  };
}
