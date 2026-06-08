{lib, ...}: {
  programs.plasma.configFile = {
    "discoverrc"."Software" = {
      UseOfflineUpdates = true;
    };
  };
}
