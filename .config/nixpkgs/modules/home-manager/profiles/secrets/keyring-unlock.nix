{
  config,
  pkgs,
  ...
}: let
  python = pkgs.python3.withPackages (packages: [packages.dbus-python]);
  unlockScript = pkgs.writeScript "unlock-gnome-keyring" ''
    #!${python}/bin/python3
    ${builtins.readFile ./keyring_unlock.py}
  '';
in {
  # Agenix secret for keyring password
  age.secrets.keyring-password = {
    file = "${config.my.secretsPath}/misc/keyring-password.age";
  };

  # Unlock the daemon used by applications; --unlock starts a competing daemon.
  systemd.user.services.gnome-keyring-unlock = {
    Unit = {
      Description = "Unlock GNOME Keyring";
      After = ["graphical-session-pre.target" "agenix.service"];
      Requires = ["agenix.service"];
      PartOf = ["graphical-session.target"];
    };

    Service = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = "${unlockScript} ${config.age.secrets.keyring-password.path}";
      TimeoutStartSec = 60;
    };

    Install = {
      WantedBy = ["graphical-session.target"];
    };
  };
}
