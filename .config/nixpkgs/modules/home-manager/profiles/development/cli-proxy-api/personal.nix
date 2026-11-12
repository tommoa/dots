{config, ...}: {
  imports = [../cli-proxy-api.nix];

  # Compose with the mail profile to reuse its personal account identities.
  my.cliProxyApi.accountPriorities = {
    "${config.accounts.email.accounts.personal.address}" = 0;
    "${config.accounts.email.accounts.tommoa.address}" = 0;
    "${config.accounts.email.accounts.shared.address}" = -10;
  };
}
