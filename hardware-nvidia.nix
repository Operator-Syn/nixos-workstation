{
  config,
  pkgs,
  lib,
  ...
}: {
  # Enable NVIDIA drivers
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
    # Also include 32-bit versions for Steam compatibility
    extraPackages32 = with pkgs.pkgsi686Linux; [
      intel-media-driver
      intel-vaapi-driver
      libvdpau-va-gl
    ];
  };

  hardware.nvidia = {
    # Modesetting is required.
    modesetting.enable = true;

    # Nvidia power management. Experimental, and can cause sleep/suspend to fail.
    powerManagement.enable = false;
    # Fine-grained power management. Turns off GPU when not in use.
    powerManagement.finegrained = true;

    # Use the NVidia open source kernel module (not to be confused with the
    # independent third-party "nouveau" open source driver).
    # Support is limited to the Turing and later architectures. Full list of
    # supported GPUs is at:
    # https://github.com/NVIDIA/open-gpu-kernel-modules#compatible-gpus
    # Only available from driver 515.43.04+
    # Do not disable this if you have a modern GPU (RTX series).
    open = false;

    # Enable the Nvidia settings menu, accessible via `nvidia-settings`.
    nvidiaSettings = true;

    # Optionally, you may need to select the appropriate driver version for your specific GPU.
    package = config.boot.kernelPackages.nvidiaPackages.stable;

    prime = {
      sync.enable = false;
      offload = {
        enable = true;
        enableOffloadCmd = true;
      };
      # Values are now pulled from the top-level config for better reproducibility
      intelBusId = lib.mkDefault config.hardware.nvidia.prime.intelBusId;
      nvidiaBusId = lib.mkDefault config.hardware.nvidia.prime.nvidiaBusId;
    };

    # prime = {
    #   offload = {
    #     enable = true;
    #     enableOffloadCmd = true;
    #   };
    #   intelBusId = "PCI:0:2:0";
    #   nvidiaBusId = "PCI:1:0:0";
    # };
  };

  hardware.nvidia-container-toolkit.enable = true;
}
