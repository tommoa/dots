{...}: {
  # SSH
  services.openssh = {
    enable = true;
    settings = {
      PasswordAuthentication = false;
      PermitRootLogin = "no";
    };
  };

  # Minimal firewall
  networking.firewall = {
    enable = true;
    allowedTCPPorts = [22];
  };
}
