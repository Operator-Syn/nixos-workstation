{
  lib,
  pkgs,
  ...
}: {
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
  environment.etc."hermes/config.yaml".text = ''
    web:
      search_backend: searxng
      extract_backend: firecrawl
    mcp_servers:
      firecrawl:
        url: https://crawl-mcp.yashindo.syn-forge.com/mcp
    memory:
      mnemosyne:
        default_scope: global
        embedding_model: nomic-ai/nomic-embed-text-v1.5
        embedding_dim: 768
        fastembed_cache_dir: /home/yashindo/.hermes/cache/fastembed-shared
  '';
}
