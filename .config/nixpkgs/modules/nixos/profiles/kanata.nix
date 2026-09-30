{...}: {
  services.kanata = {
    enable = true;
    keyboards.laptop = {
      # The layout is shared; each host supplies its own input device paths.
      config = builtins.readFile ../kanata/feral.kbd;
      extraDefCfg = "process-unmapped-keys yes";
    };
  };
}
