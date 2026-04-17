self: super: {
  yabai = super.yabai.overrideAttrs (o: rec {
    version = "7.1.18";
    src = builtins.fetchTarball {
      url = "https://github.com/koekeishiya/yabai/releases/download/v${version}/yabai-v${version}.tar.gz";
      sha256 = "09g9rbf4mhfw4baglnz209c4j7ww8z88k29cvzz3c0xy0dn140qc";
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
