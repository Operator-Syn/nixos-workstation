{
  config,
  pkgs,
  ...
}: {
  programs.fish.enable = true;

  users.users.yashindo = {
    isNormalUser = true;
    uid = 1000;
    description = "John-Ronan";
    shell = pkgs.fish;
    extraGroups = [
      "networkmanager"
      "wheel"
      "docker"
      "gamemode"
      "kvm"
      "libvirtd"
      # NixOS's PipeWire module mirrors PipeWire's upstream 25-pw-rlimits.conf.in
      # and grants rtprio 95, nice -19 and memlock to this group only (see
      # security.pam.loginLimits in nixos/modules/services/desktops/pipewire).
      # Those rules reach a session only through pam_limits at login, so a user
      # outside the group keeps RLIMIT_RTPRIO 0: PipeWire's module-rt clamps its
      # own rtprio request to 0, reports "can't set rt prio to 88 (try
      # increasing rlimits)" and applies only a nice level through RTKit,
      # leaving every audio thread at SCHED_OTHER. Membership is what lets
      # PipeWire, WirePlumber, pipewire-pulse and EasyEffects request realtime.
      # This takes effect after activation and a fresh login; check it with
      # `systemctl --user show -p LimitRTPRIO pipewire`.
      "pipewire"
    ];
    openssh.authorizedKeys.keys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIIBVknzlufRF7BJlPaATjBMyahWIWabgSsIVBkb6ElJq yashindo@hiraeth"
    ];
  };

  # `extraGroups` is a free-form list of strings, so a missing or misspelled
  # group evaluates cleanly and silently withholds the privileges it was meant to
  # grant. That is how the realtime-audio fix above failed the first time: every
  # audio thread ran at SCHED_OTHER because "pipewire" was absent, and no
  # evaluation, flake check or test suite reported it. Assert the invariant so
  # dropping the membership stops evaluation instead of only degrading live
  # audio, where it shows up as dropouts under load rather than an error.
  assertions = [
    {
      assertion =
        !config.services.pipewire.enable
        || builtins.elem "pipewire" config.users.users.yashindo.extraGroups;
      message = ''
        services.pipewire is enabled, so yashindo must stay in the "pipewire"
        group. NixOS grants that group rtprio 95, nice -19 and memlock through
        security.pam.loginLimits, and without the membership every audio thread
        runs at SCHED_OTHER with RLIMIT_RTPRIO 0.
      '';
    }
  ];
}
