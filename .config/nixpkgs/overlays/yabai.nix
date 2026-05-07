self: super: {
  yabai = super.yabai.overrideAttrs (o: rec {
    version = "7.1.24";
    src = builtins.fetchTarball {
      url = "https://github.com/koekeishiya/yabai/releases/download/v${version}/yabai-v${version}.tar.gz";
      sha256 = "1ys6c7q5rz78dxg6a04mi7mcdsrs6128kxf6x82ifnkd399xkm6q";
    };

    postPatch = '''';

    installPhase = ''
      mkdir -p $out/bin
      mkdir -p $out/share/man/man1/
      cp ./bin/yabai $out/bin/yabai
      cp ./doc/yabai.1 $out/share/man/man1/yabai.1
    '';
  });
}
