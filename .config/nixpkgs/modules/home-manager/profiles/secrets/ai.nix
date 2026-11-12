{
  config,
  lib,
  pkgs,
  ...
}: {
  # Agenix leaves direct-path copies behind when secret declarations disappear.
  # Remove retired AI and search credentials on existing machines after linking.
  home.activation.removeRetiredApiKeys = lib.hm.dag.entryAfter ["linkGeneration"] ''
    run ${pkgs.coreutils}/bin/rm -f \
      "${config.home.homeDirectory}/.config/ai-keys/anthropic" \
      "${config.home.homeDirectory}/.config/ai-keys/openai" \
      "${config.home.homeDirectory}/.config/ai-keys/opencode-zen" \
      "${config.home.homeDirectory}/.config/ai-keys/openrouter" \
      "${config.home.homeDirectory}/.config/ai-keys/gemini" \
      "${config.home.homeDirectory}/.config/ai-keys/vertex" \
      "${config.home.homeDirectory}/.config/ai-keys/vertex-project" \
      "${config.home.homeDirectory}/.config/ai-keys/vertex.tmp.stale.20260512220058" \
      "${config.home.homeDirectory}/.config/search-engines/google-api-key" \
      "${config.home.homeDirectory}/.config/search-engines/google-engine-id" \
      "${config.home.homeDirectory}/.config/search-engines/tavily-api-key"
  '';
}
