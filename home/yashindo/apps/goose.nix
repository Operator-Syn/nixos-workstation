# goose.nix
{
  pkgs,
  lib,
  config,
  ...
}: {
  options.modules.goose.enable = lib.mkEnableOption "Goose agentic AI CLI (MCP-capable)";

  config = lib.mkIf config.modules.goose.enable {
    home.packages = [pkgs.goose-cli];

    home.sessionVariables = {
      GOOSE_PROVIDER = "ollama";
      GOOSE_MODEL = "qwen3-coder:30b";
      OLLAMA_HOST = "http://127.0.0.1:11434";

      # Match your Ollama context setting.
      # Start with 32768 because 30B is heavy on 6GB VRAM.
      GOOSE_CONTEXT_LIMIT = "32768";
      GOOSE_INPUT_LIMIT = "32768";

      # Better for agentic workflows.
      GOOSE_MODE = "auto";

      # Helps local Ollama models perform Goose tool calls more reliably.
      GOOSE_TOOLSHIM = "true";
      GOOSE_TOOLSHIM_OLLAMA_MODEL = "qwen3-coder:30b";

      # Optional while diagnosing weird Goose behavior.
      GOOSE_DEBUG = "true";

      # Avoid possible shell incompatibilities during tool execution.
      GOOSE_SHELL = "${pkgs.bashInteractive}/bin/bash";
    };
  };
}
