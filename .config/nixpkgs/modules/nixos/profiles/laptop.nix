{lib, ...}: {
  services.tlp = {
    enable = true;
    # Expose TLP's profiles to the desktop and LAVD through the same D-Bus API.
    pd.enable = true;
    settings = {
      # Native switching selects performance on AC and balanced on battery,
      # while preserving profiles manually selected for the current power source.
      TLP_AUTO_SWITCH = 2;

      # This Ryzen uses acpi-cpufreq; EPP and amd-pstate are unavailable.
      CPU_SCALING_GOVERNOR_ON_AC = "schedutil";
      CPU_SCALING_GOVERNOR_ON_BAT = "schedutil";
      CPU_SCALING_GOVERNOR_ON_SAV = "schedutil";
      CPU_BOOST_ON_AC = 1;
      CPU_BOOST_ON_BAT = 1;
      CPU_BOOST_ON_SAV = 0;

      # TLP 1.9 shares this GPU setting between balanced and power-saver.
      # Retain automatic clocks so battery use does not force the lowest clock.
      RADEON_DPM_PERF_LEVEL_ON_AC = "auto";
      RADEON_DPM_PERF_LEVEL_ON_BAT = "auto";

      # Panel savings trade colour accuracy for lower power consumption.
      AMDGPU_ABM_LEVEL_ON_AC = 0;
      AMDGPU_ABM_LEVEL_ON_BAT = 1;
      AMDGPU_ABM_LEVEL_ON_SAV = 3;
    };
  };

  # Let LAVD follow the profiles advertised by tlp-pd.
  services.scx.extraArgs = ["--autopower"];

  # LAVD stops trying to connect after ten failed D-Bus reads. Start it after
  # tlp-pd is ready; use graphical.target because tlp-pd starts after multi-user.
  systemd.services.scx = {
    wantedBy = lib.mkForce ["graphical.target"];
    wants = ["tlp-pd.service"];
    after = ["tlp-pd.service"];
  };
}
