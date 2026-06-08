{
  config,
  pkgs,
  ...
}: {
  boot.kernelParams = [
    "nvidia_drm.modeset=1"
    "nvidia_drm.fbdev=1"
    "nvidia.NVreg_PreserveVideoMemoryAllocations=1"
  ];

  services.xserver.videoDrivers = ["nvidia"];

  hardware.graphics = {
    enable = true;
    enable32Bit = true;
    extraPackages = with pkgs; [
      # Video Acceleration (VA-API/VDPAU)
      intel-media-driver # For modern Intel iGPU video
      intel-vaapi-driver # For older Intel video compatibility
      nvidia-vaapi-driver # For NVIDIA video decoding
      libvdpau-va-gl # Bridge for older apps

      # Compute (OpenCL/Vulkan)
      intel-compute-runtime # Enables OpenCL on Intel (essential for some AI/render apps)
      vulkan-loader # Ensures Vulkan ICDs are visible to applications
      vulkan-validation-layers # Useful for development and stability
    ];
    extraPackages32 = with pkgs.pkgsi686Linux; [
      intel-media-driver
      intel-vaapi-driver
      libvdpau-va-gl
    ];
  };

  hardware.nvidia = {
    modesetting.enable = true;

    powerManagement.enable = false;
    powerManagement.finegrained = true;

    open = false;

    nvidiaSettings = true;

    package = config.boot.kernelPackages.nvidiaPackages.stable;

    prime = {
      sync.enable = false;
      offload = {
        enable = true;
        enableOffloadCmd = true;
      };
      intelBusId = "PCI:0:2:0";
      nvidiaBusId = "PCI:1:0:0";
    };
  };

  hardware.nvidia-container-toolkit.enable = true;
}
