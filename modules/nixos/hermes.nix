{
  lib,
  pkgs,
  config,
  ...
}: let
  # Path depth from this file (modules/nixos/) to the repo root is TWO levels;
  # a third "../" escapes the flake source, so pathExists was always false and
  # sops.secrets.hermes_env was never declared.
  hermesEnvSecretFile = ../../secrets/hermes-env.yaml;
  hasHermesEnvSecretFile = builtins.pathExists hermesEnvSecretFile;
in {
  config = {
    # IT-managed Hermes scope. Hermes reads /etc/hermes/config.yaml as an
    # administrator-pinned overlay that the user cannot override with
    # `hermes config set` (filesystem-permission enforcement, see the
    # managed-scope design note upstream).
    #
    # default_scope: global is the reason this file exists: without it Mnemosyne
    # scopes every new memory to the session that created it, and recall only
    # returns `session_id = current OR scope = 'global'`, so session memories die
    # with their session instead of persisting.
    #
    # NOTE: the Mnemosyne provider does not consult this managed overlay on its
    # config path (it reads the Hermes/Mnemosyne config files directly), so the
    # home-manager activation `hermesMnemosyneDefaultScope` asserts the same value
    # in the Mnemosyne config files. Keep the two in sync.
    #
    # providers.lm-studio: a LAN LM Studio (OpenAI-compatible) custom endpoint
    # registered here so every profile — existing and future — inherits it without
    # per-profile wiring. Profiles do NOT inherit ~/.hermes/config.yaml, so the
    # managed overlay is the only cross-profile seam. Being managed, the pinned
    # leaves are immutable: change this file (not `hermes config set`) to move it.
    #
    # No `models:` catalog and no default `model:` on purpose — this pins only the
    # endpoint identity, and both are deliberately left unmanaged so they stay
    # dynamic: `discover_models: true` makes the live server's /v1/models the source
    # of truth (models may be swapped in LM Studio freely), and each profile can still
    # set its own default model with `hermes config set providers.lm-studio.model …`.
    #
    # providers.codex-proxy: the locally hosted Codex Proxy gateway — an
    # OpenAI-compatible pool in front of Codex subscription accounts, served by
    # Traefik at http://localhost:8080/api/v1. Registered here for the same reason
    # as lm-studio: the managed overlay is the one seam that covers every profile,
    # existing and future, so a new profile reaches the proxy with no wiring.
    #
    # `transport: codex_responses` selects the proxy's native Responses route, so a
    # client POSTs to {base_url}/responses. As with lm-studio there is no `models:`
    # catalog and no default `model:` — `discover_models: true` takes the proxy's
    # authenticated GET /api/v1/models as the source of truth, and each profile
    # picks its own default with `hermes config set model.default …`.
    #
    # The credential is CODEX_PROXY_API_KEY (a `usr_…` proxy key) and lives only in
    # the sops-managed /etc/hermes/.env below — never inline in this file. The proxy
    # requires it even to list models, so discovery depends on it too.
    environment.etc."hermes/config.yaml".text = ''
      web:
        # Brave Search (free tier) via BRAVE_SEARCH_API_KEY. Search-only provider,
        # so extraction stays on firecrawl.
        search_backend: brave-free
        extract_backend: firecrawl
        # Keyless free-tier ring (Exa / Parallel / Firecrawl / Keenable).
        # keyless_rescue is inoperative unless keyless_fallback is also on; it
        # retries a *failed* call once on the ring and reports rescued_from /
        # backend_error. It does NOT cover an empty-but-successful result.
        # Pinned here because profiles do NOT inherit ~/.hermes/config.yaml, so
        # this overlay is the only seam covering future profiles too.
        keyless_fallback: true
        keyless_rescue: true
      mcp_servers:
        firecrawl:
          url: https://crawl-mcp.yashindo.syn-forge.com/mcp
      providers:
        lm-studio:
          name: LM Studio
          base_url: http://192.168.1.8:1234/v1
          discover_models: true
        codex-proxy:
          name: Codex Proxy
          base_url: http://localhost:8080/api/v1
          transport: codex_responses
          key_env: CODEX_PROXY_API_KEY
          discover_models: true
      memory:
        mnemosyne:
          default_scope: global
          embedding_model: nomic-ai/nomic-embed-text-v1.5
          embedding_dim: 768
          fastembed_cache_dir: /home/yashindo/.hermes/cache/fastembed-shared
    '';

    # sops secret for the complete /etc/hermes/.env — SEARXNG_URL, FIRECRAWL_API_URL,
    # OPENROUTER_API_KEY, NVIDIA_API_KEY, BRAVE_SEARCH_API_KEY, CODEX_PROXY_API_KEY.
    # The NVIDIA/OpenRouter keys are load-bearing for non-default profiles: they
    # declare `provider: nvidia` as a fallback and carry no key of their own.
    # CODEX_PROXY_API_KEY backs providers.codex-proxy above.
    # NixOS context: `config.home` only exists inside home-manager modules, so use
    # the NixOS-native user home path (matches how debian-container.nix does it).
    sops.age.keyFile = lib.mkIf hasHermesEnvSecretFile "${config.users.users.yashindo.home}/.config/sops/age/keys.txt";

    sops.secrets.hermes_env = lib.mkIf hasHermesEnvSecretFile {
      sopsFile = hermesEnvSecretFile;
      key = "dotenv_content";
      path = "/etc/hermes/.env";
      mode = "0640";
      owner = "root";
      group = "users";
    };
  };
}
