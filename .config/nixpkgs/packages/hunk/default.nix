# hunk: review-first terminal diff viewer for agent-authored changesets
#
# Upstream publishes the CLI as the npm package `hunkdiff`, with small metadata
# tarballs and platform-specific optional binary packages.
{
  lib,
  stdenv,
  fetchurl,
  autoPatchelfHook,
}: let
  version = "0.10.0";

  packageSrc = fetchurl {
    url = "https://registry.npmjs.org/hunkdiff/-/hunkdiff-${version}.tgz";
    hash = "sha512-GfUYNCzEnZ0OTdg340YRFbW1SvvwgRMyQmn44t2GKoSjYqiXGaDCeOG66fpIzU8WRdbUi2uzdGIVkEsCps8TeA==";
  };

  sources = {
    aarch64-darwin = {
      npmPackage = "hunkdiff-darwin-arm64";
      hash = "sha512-oJALanUcIFp19LQbTTNKEk/RA0QIeeqwXzUciTzBlze1IA5GPe+rq+OLy66fFUA5tiO6qj6sXf1UqK9cL8o0Mw==";
    };
    x86_64-darwin = {
      npmPackage = "hunkdiff-darwin-x64";
      hash = "sha512-5sVwIN7OQ4x6/K1TfP4n0wUZinL9nPKmbZ/oHJWhMD6FScGuOOYYZQtN+q2j3ahzlu36Iio7OXajuyQZulwU4A==";
    };
    aarch64-linux = {
      npmPackage = "hunkdiff-linux-arm64";
      hash = "sha512-h3yY1cxEmer3StCppvQ4kZyK10971t6dMO76jMnWNhREWML2H2hCiPrNw5Yjx0tI0AyI1P4D3guNCcvylLmO4A==";
    };
    x86_64-linux = {
      npmPackage = "hunkdiff-linux-x64";
      hash = "sha512-me3Pl6Tqb46yoZP930iCUdE3pE5lDOtfsWUcCZXqEpsg0WPbW6PjO6tjX7MRnkLFPacPDrqfPZpEHr2bxK0X9A==";
    };
  };

  platform = stdenv.hostPlatform.system;
  source = sources.${platform} or (throw "hunk: unsupported platform ${platform}");
  binarySrc = fetchurl {
    url = "https://registry.npmjs.org/${source.npmPackage}/-/${source.npmPackage}-${version}.tgz";
    inherit (source) hash;
  };
in
  stdenv.mkDerivation {
    pname = "hunk";
    inherit version;

    srcs = [
      packageSrc
      binarySrc
    ];
    sourceRoot = ".";

    nativeBuildInputs = lib.optionals stdenv.hostPlatform.isLinux [autoPatchelfHook];
    buildInputs = lib.optionals stdenv.hostPlatform.isLinux [stdenv.cc.cc.lib];

    dontConfigure = true;
    dontBuild = true;

    unpackPhase = ''
      runHook preUnpack
      mkdir package binary
      tar -xzf ${packageSrc} -C package --strip-components=1
      tar -xzf ${binarySrc} -C binary --strip-components=1
      runHook postUnpack
    '';

    installPhase = ''
      runHook preInstall
      install -Dm755 binary/bin/hunk $out/bin/hunk
      install -Dm644 package/skills/hunk-review/SKILL.md \
        $out/share/hunk/skills/hunk-review/SKILL.md
      install -Dm644 package/README.md $out/share/doc/hunk/README.md
      install -Dm644 package/LICENSE $out/share/licenses/hunk/LICENSE
      runHook postInstall
    '';

    doInstallCheck = true;
    installCheckPhase = ''
      $out/bin/hunk --version
    '';

    meta = {
      description = "Review-first terminal diff viewer for agent-authored changesets";
      homepage = "https://github.com/modem-dev/hunk";
      license = lib.licenses.mit;
      mainProgram = "hunk";
      platforms = builtins.attrNames sources;
    };
  }
