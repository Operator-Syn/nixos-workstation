{
  config,
  pkgs,
  ...
}: {
  boot.kernelParams = [
    "nvidia_drm.fbdev=1"
    "nvidia.NVreg_PreserveVideoMemoryAllocations=1"
  ];

  services.xserver.videoDrivers = ["nvidia"];

  hardware.graphics = {
    enable = true;
    enable32Bit = true;
    extraPackages = with pkgs; [
      # Video Acceleration (VA-API/VDPAU)
      nvidia-vaapi-driver # For NVIDIA video decoding
      libvdpau-va-gl # Bridge for older apps

      # Compute (OpenCL/Vulkan)
      vulkan-loader # Ensures Vulkan ICDs are visible to applications
      vulkan-validation-layers # Useful for development and stability
    ];
    extraPackages32 = with pkgs.pkgsi686Linux; [
      libvdpau-va-gl
    ];
  };

  hardware.nvidia = {
    modesetting.enable = true;

    powerManagement.enable = false;
    powerManagement.finegrained = true;

    # Enable NVIDIA Dynamic Boost on AC power. Without nvidia-powerd, this
    # laptop remains at its 40 W base limit instead of using its firmware
    # performance envelope under GPU load.
    dynamicBoost.enable = true;

    # The RTX 4050 is an Ada GPU supported by NVIDIA's open kernel modules.
    # The open path is required for compatibility with the Armoury-capable
    # kernel selected in hosts/hiraeth/boot.nix.
    open = true;

    nvidiaSettings = true;

    package = config.boot.kernelPackages.nvidiaPackages.latest;

    prime = {
      sync.enable = false;
      offload = {
        enable = true;
        enableOffloadCmd = true;
      };
      amdgpuBusId = "PCI:6:0:0";
      nvidiaBusId = "PCI:1:0:0";
    };
  };

  # The userspace driver (libcuda.so.1) is installed under
  # /run/opengl-driver/lib, which is not on the dynamic loader search path for
  # "foreign" (non-Nix) ELF binaries. The uv-managed CPython that runs
  # TensorFlow and JupyterLab is such a binary, so it cannot dlopen libcuda.so.1
  # even though nvidia-smi (a Nix binary carrying its own RUNPATH) works.
  #
  # nix-ld is NixOS's designed extension point for foreign binaries. Adding the
  # driver's userspace libraries here puts them on the loader path for foreign
  # binaries only; Nix binaries keep their own RPATHs and are untouched, so no
  # global LD_LIBRARY_PATH is needed. libcuda.so.1 resolves its sibling driver
  # libraries through its own RUNPATH into this same package.
  programs.nix-ld.libraries = [config.hardware.nvidia.package];

  hardware.nvidia-container-toolkit.enable = true;
}
