{
  config,
  pkgs,
  ...
}: {
  # Agenix secret for keyring password
  age.secrets.keyring-password = {
    file = "${config.my.secretsPath}/misc/keyring-password.age";
  };

  # Systemd user service to unlock gnome-keyring at login
  systemd.user.services.gnome-keyring-unlock = {
    Unit = {
      Description = "Unlock GNOME Keyring";
      # Run after graphical session starts (keyring is started by PAM during login)
      After = ["graphical-session-pre.target"];
      PartOf = ["graphical-session.target"];
    };

    Service = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = let
        unlockScript = pkgs.writeShellScript "unlock-gnome-keyring" ''
          # Wait for keyring control socket to be available (up to 5 seconds)
          for i in $(seq 1 10); do
            [ -S "$XDG_RUNTIME_DIR/keyring/control" ] && break
            sleep 0.5
          done

          # Check if keyring control socket exists
          if [ ! -S "$XDG_RUNTIME_DIR/keyring/control" ]; then
            echo "Keyring control socket not found after waiting, keyring may not be running" >&2
            exit 1
          fi

          # Read the password from the agenix secret and unlock
          if [ -f "${config.age.secrets.keyring-password.path}" ]; then
            ${pkgs.gnome-keyring}/bin/gnome-keyring-daemon --unlock < "${config.age.secrets.keyring-password.path}"
            echo "Keyring unlocked successfully"
          else
            echo "Keyring password file not found: ${config.age.secrets.keyring-password.path}" >&2
            exit 1
          fi
        '';
      in "${unlockScript}";
    };

    Install = {
      WantedBy = ["graphical-session.target"];
    };
  };
}
