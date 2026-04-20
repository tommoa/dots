self: super: {
  yabai = super.yabai.overrideAttrs (o: rec {
    version = "7.1.23";
    src = builtins.fetchTarball {
      url = "https://github.com/koekeishiya/yabai/releases/download/v${version}/yabai-v${version}.tar.gz";
      sha256 = "1qrbn149arkd3zw8sc0ghkz3w0548y1w6j0kj57s743612wcghm7";
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
