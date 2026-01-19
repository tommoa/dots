{pkgs, ...}: {
  # Make sure that GDM is running.
  services.displayManager.gdm.enable = true;

  # Audio
  services.pulseaudio.enable = false;
  security.rtkit.enable = true;
  services.pipewire = {
    enable = true;
    alsa.enable = true;
    alsa.support32Bit = true;
    pulse.enable = true;
  };

  # Printing
  services.printing.enable = true;

  # Desktop programs
  programs.hyprland = {
    enable = true;
    withUWSM = true;
    xwayland.enable = true;
  };

  # GUI for managing GNOME keyring secrets
  programs.seahorse.enable = true;

  # Gaming
  programs.steam = {
    enable = true;
    remotePlay.openFirewall = true;
    localNetworkGameTransfers.openFirewall = true;
  };

  # Gracefully stop Steam before shutdown to prevent mount hangs.
  # Uses shutdown-only pattern: service starts (runs ExecStart) only during shutdown,
  # so it won't interfere with nixos-rebuild.
  systemd.services.steam-shutdown = {
    description = "Gracefully stop Steam before shutdown";
    wantedBy = [
      "halt.target"
      "poweroff.target"
      "reboot.target"
    ];
    before = [
      "halt.target"
      "poweroff.target"
      "reboot.target"
      "umount.target"
    ];
    unitConfig = {
      DefaultDependencies = false;
    };
    serviceConfig = {
      Type = "oneshot";
      ExecStart = let
        stopScript = pkgs.writeShellScript "shutdown-steam" ''
          # Check if the main Steam process is running
          if ${pkgs.procps}/bin/pgrep -x steam > /dev/null 2>&1; then
            echo "Stopping Steam gracefully..."
            # Send TERM signal to Steam processes (exact match to avoid killing this script)
            ${pkgs.procps}/bin/pkill -TERM -x steam || true

            # Wait up to 15 seconds for Steam to exit
            for i in $(seq 1 15); do
              if ! ${pkgs.procps}/bin/pgrep -x steam > /dev/null 2>&1; then
                echo "Steam stopped gracefully"
                exit 0
              fi
              sleep 1
            done

            # Force kill if still running
            echo "Force killing remaining Steam processes..."
            ${pkgs.procps}/bin/pkill -9 -x steam || true
            sleep 1
          fi
          echo "Steam shutdown complete"
        '';
      in "${stopScript}";
      TimeoutStartSec = 25;
    };
  };

  # Environment variables
  environment.sessionVariables = {
    NIXOS_OZONE_WL = "1";
    SDL_VIDEODRIVER = "wayland";
  };
}
