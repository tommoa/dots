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
  peter = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAILwOf/6WNYLpglqjui8xc2cBtU3u47f4CNv0++1yvMVQ peter-agenix";

  # Dedicated persistent agenix identity; does not enable an SSH server.
  james = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIKMofYrxsoa44IDJ8dfORRGDfa0jZGEEKd7SD87jNPWP james-agenix";

  # All users who can edit secrets
  users = [toma];

  # All systems that need access to secrets
  allSystems = [apollo];

  # Combined: users (for editing) + systems (for runtime decryption)
  all = users ++ allSystems;

  # Work-specific secrets (user + work host only)
  workSecrets = users ++ [work];

  # Personal desktop secrets (user + apollo host only). Keep these out of
  # work-host deployments even though the same user can edit them.
  personalSecrets = users ++ [apollo];
in {
  # AI API keys
  "ai/anthropic.age".publicKeys = all;
  "ai/openai.age".publicKeys = all;
  "ai/opencode-zen.age".publicKeys = all;
  "ai/openrouter.age".publicKeys = all;
  "ai/litellm.age".publicKeys = workSecrets;

  # Mozilla Add-ons signing credentials
  "amo/api-key.age".publicKeys = workSecrets;
  "amo/api-secret.age".publicKeys = workSecrets;

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

  # Arista status report pipeline
  "arista-report/arista-report.age".publicKeys = workSecrets;
  "arista-report/arista-report-passrates.age".publicKeys = workSecrets;
  "arista-report/arista-report-bugs.age".publicKeys = workSecrets;
  "arista-report/arista-report-bugdetail.age".publicKeys = workSecrets;
  "arista-report/arista-report-merged.age".publicKeys = workSecrets;
  "arista-report/arista-report-reviews.age".publicKeys = workSecrets;
  "arista-report/arista-report-arastra.age".publicKeys = workSecrets;

  "arista-report/arista-report-format.age".publicKeys = workSecrets;
  "arista-report/arista-report-lib.age".publicKeys = workSecrets;
  "arista-report/arista-status-report-skill.age".publicKeys = workSecrets;

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
  "ssh/config-home-bus.age".publicKeys = workSecrets;

  # Misc secrets
  "misc/cargo-credentials.age".publicKeys = all;
  "misc/gpg-agent-conf.age".publicKeys = all;
  # The Git signing subkey is user-scoped; do not give host keys access to it.
  "misc/git-signing-subkey.age".publicKeys = users;
  # Email refresh tokens need the existing personal GPG encryption subkey.
  "misc/mail-encryption-subkey.age".publicKeys = users;

  # Keyring unlock password (for auto-login systems)
  "misc/keyring-password.age".publicKeys = all;

  # Shared login password for Peter and James; toma remains an editing recipient.
  "misc/peter-login-hash.age".publicKeys = users ++ [peter james];
}
