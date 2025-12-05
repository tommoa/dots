# Agenix secrets configuration
# This file maps secrets to the public keys that can decrypt them.
# DO NOT import this file into your NixOS/nix-darwin/home-manager configuration!
# It is only used by the agenix CLI for encryption/decryption.
let
  # User keys - for editing secrets locally
  toma = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIIS8KG2iv8MsZZ/hCA3P4qbBHign34LAjbBt4zdIG73D";

  # Host keys - for decryption on target machines
  # Get with: cat /etc/ssh/ssh_host_ed25519_key.pub
  apollo = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIF8+lrFue2t9h3ABGeeQqNv9pIrZssrU81Nn/YErJfpE";
  work = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIBHPfVFfiXyMhtsZzuuoZq4Au8VIqODHKMxpE6RWLnJO";

  # TODO: Get james host key with: ssh-keyscan -t ed25519 james
  # james = "ssh-ed25519 AAAA...";

  # All users who can edit secrets
  users = [ toma ];

  # All systems that need access to secrets
  # Add james here once you have the host key
  allSystems = [ apollo ];

  # Combined: users (for editing) + systems (for runtime decryption)
  all = users ++ allSystems;

  # Work-specific secrets (user + work host only)
  workSecrets = users ++ [ work ];

in
{
  # AI API keys
  "ai/anthropic.age".publicKeys = all;
  "ai/gemini.age".publicKeys = all;
  "ai/openai.age".publicKeys = all;
  "ai/openrouter.age".publicKeys = all;
  "ai/vertex.age".publicKeys = all ++ workSecrets;
  "ai/vertex-project.age".publicKeys = all ++ workSecrets;

  # Mail secrets
  # Note: Refresh tokens are stored locally per-machine in ~/.local/state/oauth2-gmail/
  # and are NOT managed by agenix (they are obtained via oauth2-gmail setup)
  "mail/personal-oauth2-client-id.age".publicKeys = all;
  "mail/personal-oauth2-client-secret.age".publicKeys = all;
  "mail/work-oauth2-client-id.age".publicKeys = all;
  "mail/work-oauth2-client-secret.age".publicKeys = all;
  "mail/shared-oauth2-client-id.age".publicKeys = all;
  "mail/shared-oauth2-client-secret.age".publicKeys = all;
  "mail/tommoa-password.age".publicKeys = all;
  "mail/aerc-keyring.age".publicKeys = all;

  # Search engine API keys
  "search-engines/google-api-key.age".publicKeys = all;
  "search-engines/google-engine-id.age".publicKeys = all;
  "search-engines/tavily-api-key.age".publicKeys = all;

  # SSH deploy keys
  # NOTE: id_ed25519 is NOT managed by agenix - it's the identity used to decrypt
  # other secrets, so it must be available before agenix runs. It remains in
  # ~/.secrets and is symlinked by setup.sh.
  "ssh/github-deploy.age".publicKeys = all;
  "ssh/github-deploy-pub.age".publicKeys = all;
  "ssh/srht-deploy.age".publicKeys = all ++ workSecrets;
  "ssh/srht-deploy-pub.age".publicKeys = all ++ workSecrets;

  # SSH config fragments (sensitive host configurations)
  "ssh/config-work.age".publicKeys = all ++ workSecrets;
  "ssh/config-servers.age".publicKeys = all;
  "ssh/config-arista-bus.age".publicKeys = all;

  # Misc secrets
  "misc/cargo-credentials.age".publicKeys = all;
  "misc/gpg-agent-conf.age".publicKeys = all;
}
