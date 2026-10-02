{
  buildNpmPackage,
  fetchFromGitiles,
  jq,
  lib,
  nodejs_22,
  runCommand,
  zip,
  aristaMetadata ? builtins.fromJSON (builtins.readFile ./metadata.json),
}: let
  source = fetchFromGitiles {
    url = "https://gerrit.corp.arista.io/plugins/gitiles/tools/arista-browser-extension";
    rev = aristaMetadata.rev;
    hash = aristaMetadata.sourceHash;
  };

  # Patch before building so the AMO source archive and signed payload share one identity.
  patchedSource = runCommand "arista-browser-extension-${aristaMetadata.upstreamVersion}-source" {} ''
    mkdir -p "$out"
    cp -R ${source}/. "$out/"
    chmod -R u+w "$out"

    substituteInPlace "$out/src/manifest.ts" \
      --replace-fail ${lib.escapeShellArg ''name: "Arista Browser Extension"''} ${lib.escapeShellArg "name: ${builtins.toJSON aristaMetadata.displayName}"} \
      --replace-fail ${lib.escapeShellArg ''description: "Arista Browser Extension"''} ${lib.escapeShellArg "description: ${builtins.toJSON aristaMetadata.displayName}"}

    substituteInPlace "$out/fix-ff-manifest.js" \
      --replace-fail ${lib.escapeShellArg ''id: "arista-firefox-extension@arista.com"''} ${lib.escapeShellArg "id: ${builtins.toJSON aristaMetadata.addonId}"}

    find "$out" -exec touch -h -t 198001010000 {} +
  '';
in
  buildNpmPackage {
    pname = "arista-browser-extension";
    version = aristaMetadata.upstreamVersion;

    src = patchedSource;

    npmDepsHash = aristaMetadata.npmDepsHash;
    nodejs = nodejs_22;
    npmBuildScript = "build:firefox";

    nativeBuildInputs = [
      jq
      zip
    ];

    postBuild = ''
      jq -e --arg addonId ${lib.escapeShellArg aristaMetadata.addonId} \
        --arg displayName ${lib.escapeShellArg aristaMetadata.displayName} \
        --arg version ${lib.escapeShellArg aristaMetadata.upstreamVersion} \
        '.browser_specific_settings.gecko.id == $addonId and .name == $displayName and .version == $version' \
        build/manifest.json >/dev/null
    '';

    doCheck = true;
    checkPhase = ''
      runHook preCheck
      npm test
      runHook postCheck
    '';

    installPhase = ''
      runHook preInstall

      # Vite's build metadata is not extension content; web-ext excludes hidden files.
      rm -rf build/.vite
      mkdir -p "$out/unpacked"
      cp -R build/. "$out/unpacked/"
      (cd ${patchedSource}; find . -mindepth 1 -print | LC_ALL=C sort | zip -q -X "$out/source.zip" -@)

      runHook postInstall
    '';

    passthru = {
      addonId = aristaMetadata.addonId;
      displayName = aristaMetadata.displayName;
      upstreamRev = aristaMetadata.rev;
    };

    meta = {
      description = "Arista Browser Extension Firefox build";
      homepage = "https://gerrit.corp.arista.io/plugins/gitiles/tools/arista-browser-extension";
      license = lib.licenses.mit;
      platforms = ["aarch64-darwin"];
    };
  }
