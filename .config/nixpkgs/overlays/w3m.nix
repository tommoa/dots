self: super: let
  inherit (super) lib stdenv;

  # On Darwin, use "none" as a dummy backend. The configure script only
  # recognises x11/fb/fb+s/win, so "none" is silently ignored, but
  # --enable-image=none still defines USE_IMAGE=1, enabling the inline
  # image protocols (sixel, kitty, iTerm2, mlterm) in terms.c / rc.c.
  # Without an explicit value, --enable-image defaults to x11.
  imageBackends =
    lib.optional (!stdenv.hostPlatform.isDarwin) "fb"
    ++ lib.optional (!stdenv.hostPlatform.isDarwin) "x11";
  imageFlag =
    if imageBackends == []
    then "--enable-image=none"
    else "--enable-image=${lib.concatStringsSep "," imageBackends}";

  # Build tats/w3m locally — NOT exported as `w3m` to avoid rebuild cascade.
  # Replacing the `w3m` attribute would cause w3m-batch → xmlto → zeromq →
  # fontforge → dejavu-fonts → fontconfig → everything to rebuild.
  w3mTats =
    (super.w3m.override {
      graphicsSupport = true;
      x11Support = !stdenv.hostPlatform.isDarwin;
      w3m = super.w3m;
    }).overrideAttrs
    (old: rec {
      version = "0.5.3+git20230121";

      src = super.fetchFromGitHub {
        owner = "tats";
        repo = "w3m";
        rev = "v${version}";
        hash = "sha256-upb5lWqhC1jRegzTncIz5e21v4Pw912FyVn217HucFs=";
      };

      buildInputs = old.buildInputs ++ [super.libsixel];

      configureFlags =
        [
          "--with-ssl=${super.openssl.dev}"
          "--with-gc=${super.boehmgc.dev}"
          "CFLAGS=-std=gnu17"
        ]
        ++ lib.optionals (stdenv.buildPlatform != stdenv.hostPlatform) [
          "ac_cv_func_setpgrp_void=${lib.boolToYesNo (!stdenv.hostPlatform.isBSD)}"
        ]
        ++ [imageFlag]
        ++ lib.optional stdenv.hostPlatform.isDarwin "--without-x";

      postInstall = lib.optionalString (!stdenv.hostPlatform.isDarwin) ''
        ln -s $out/libexec/w3m/w3mimgdisplay $out/bin
      '';

      passthru = {};

      meta =
        old.meta
        // {
          homepage = "https://github.com/tats/w3m";
          changelog = "https://github.com/tats/w3m/blob/v${version}/NEWS";
        };
    });
in {
  # Wrapper that adds imagemagick (kitty protocol) and libsixel (sixel
  # protocol) to PATH. Separate from w3m to avoid circular dependency
  # (imagemagick → fontconfig → dejavu-fonts → fontforge → zeromq →
  # xmlto → w3m-batch → w3m).
  w3m-images = super.symlinkJoin {
    name = "w3m-images-${w3mTats.version}";
    paths = [w3mTats];
    nativeBuildInputs = [super.makeWrapper];
    postBuild = ''
      wrapProgram $out/bin/w3m \
        --prefix PATH : ${
        lib.makeBinPath [
          super.imagemagick
          super.libsixel
        ]
      }
    '';
    meta =
      w3mTats.meta
      // {
        description = "w3m with imagemagick and libsixel for inline image protocols";
      };
  };
}
