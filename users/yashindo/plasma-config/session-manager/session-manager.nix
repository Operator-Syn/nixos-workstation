{...}: {
  programs.plasma.configFile = {
    "ksmserverrc"."General" = {
      loginMode = "emptySession";
    };
  };
}
