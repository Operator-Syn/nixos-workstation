# modules/nixos/ollama.nix
{
  config,
  lib,
  ...
}: {
  options.modules.ollama.enable = lib.mkEnableOption "Ollama local LLM server";

  config = lib.mkIf config.modules.ollama.enable {
    services.ollama = {
      enable = true;
      acceleration = "cuda";

      environmentVariables = {
        # Safer starting point for RTX 4050 6GB.
        # Raise to 65536 only if performance is acceptable.
        OLLAMA_CONTEXT_LENGTH = "32768";
      };

      # Agentic coding model. Heavy on 6GB VRAM; expect RAM/CPU offloading.
      # loadModels = [
      #   "qwen3-coder:30b"
      # ];
    };
  };
}
