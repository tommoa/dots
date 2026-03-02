# mdiff (mutiny-diff): TUI git diff viewer with worktree management
#
# Pre-built binary package fetched from GitHub Releases.
# https://github.com/mutinyhq/mdiff
#
# Linux binaries are built with `cross` (cross-rs) on GitHub Actions,
# linking against glibc. autoPatchelfHook fixes the ELF interpreter/RPATH.
# macOS binaries only depend on /usr/lib/libSystem.B.dylib and need no fixup.
{
  lib,
  stdenv,
  fetchurl,
  autoPatchelfHook,
}: let
  version = "0.1.10";

  sources = {
    aarch64-darwin = {
      url = "https://github.com/mutinyhq/mdiff/releases/download/v${version}/mdiff-aarch64-apple-darwin.tar.gz";
      hash = "sha256-NAZkMhMxE9w9lMyaDaNmYlcPdtFSk/H5rsSJCw16wf4=";
    };
    x86_64-linux = {
      url = "https://github.com/mutinyhq/mdiff/releases/download/v${version}/mdiff-x86_64-unknown-linux-gnu.tar.gz";
      hash = "sha256-gOPw+yefV1SAjsx00VNqt0HCWTUNGqUwLAzJ6y4QJDw=";
    };
    aarch64-linux = {
      url = "https://github.com/mutinyhq/mdiff/releases/download/v${version}/mdiff-aarch64-unknown-linux-gnu.tar.gz";
      hash = "sha256-EC8QE+Y6H71L5xh9+A8ZniokI235ynfeGMS2biRP7t8=";
    };
  };

  # Map Nix system to the upstream target triple used in tarball paths
  targetMap = {
    aarch64-darwin = "aarch64-apple-darwin";
    x86_64-linux = "x86_64-unknown-linux-gnu";
    aarch64-linux = "aarch64-unknown-linux-gnu";
  };

  platform = stdenv.hostPlatform.system;
  src = fetchurl (sources.${platform} or (throw "mdiff: unsupported platform ${platform}"));
  target = targetMap.${platform};
in
  stdenv.mkDerivation {
    pname = "mdiff";
    inherit version src;

    # fetchurl stores the raw tarball; we need to unpack it
    sourceRoot = "mdiff-${target}";

    nativeBuildInputs = lib.optionals stdenv.hostPlatform.isLinux [autoPatchelfHook];

    # autoPatchelfHook resolves shared libs from buildInputs.
    # The cross-compiled Linux binary links against glibc (implicit via stdenv)
    # and libgcc_s.so.1 (from stdenv.cc.cc.lib).
    buildInputs = lib.optionals stdenv.hostPlatform.isLinux [
      stdenv.cc.cc.lib
    ];

    dontConfigure = true;
    dontBuild = true;

    installPhase = ''
      runHook preInstall
      install -Dm755 mdiff $out/bin/mdiff
      runHook postInstall
    '';

    # Smoke test: --help should work without a display server
    doInstallCheck = true;
    installCheckPhase = ''
      $out/bin/mdiff --help > /dev/null
    '';

    meta = {
      description = "TUI git diff viewer with worktree management";
      homepage = "https://github.com/mutinyhq/mdiff";
      license = lib.licenses.mit;
      mainProgram = "mdiff";
      platforms = builtins.attrNames sources;
    };
  }
