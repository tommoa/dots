{
  buildNpmPackage,
  fetchFromGitiles,
  jq,
  lib,
  nodejs_22,
  runCommand,
  zip,
  metadata ? builtins.fromJSON (builtins.readFile ./metadata.json),
}:
let
  source = fetchFromGitiles {
    url = "https://gerrit.corp.arista.io/plugins/gitiles/tools/arista-browser-extension";
    rev = metadata.rev;
    hash = metadata.sourceHash;
  };

  # Patch before building so the AMO source archive and signed payload share one identity.
  patchedSource = runCommand "arista-browser-extension-${metadata.upstreamVersion}-source" { } ''
    mkdir -p "$out"
    cp -R ${source}/. "$out/"
    chmod -R u+w "$out"

    substituteInPlace "$out/src/manifest.ts" \
      --replace-fail ${lib.escapeShellArg ''name: "Arista Browser Extension"''} ${lib.escapeShellArg "name: ${builtins.toJSON metadata.displayName}"} \
      --replace-fail ${lib.escapeShellArg ''description: "Arista Browser Extension"''} ${lib.escapeShellArg "description: ${builtins.toJSON metadata.displayName}"}

    substituteInPlace "$out/fix-ff-manifest.js" \
      --replace-fail ${lib.escapeShellArg ''id: "arista-firefox-extension@arista.com"''} ${lib.escapeShellArg "id: ${builtins.toJSON metadata.addonId}"}

    find "$out" -exec touch -h -t 198001010000 {} +
  '';
in
buildNpmPackage {
  pname = "arista-browser-extension";
  version = metadata.upstreamVersion;

  src = patchedSource;

  npmDepsHash = metadata.npmDepsHash;
  nodejs = nodejs_22;
  npmBuildScript = "build:firefox";

  nativeBuildInputs = [
    jq
    zip
  ];

  postBuild = ''
    jq -e --arg addonId ${lib.escapeShellArg metadata.addonId} \
      --arg displayName ${lib.escapeShellArg metadata.displayName} \
      --arg version ${lib.escapeShellArg metadata.upstreamVersion} \
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

    mkdir -p "$out/unpacked"
    cp -R build/. "$out/unpacked/"
    (cd ${patchedSource}; find . -mindepth 1 -print | LC_ALL=C sort | zip -q -X "$out/source.zip" -@)

    runHook postInstall
  '';

  passthru = {
    addonId = metadata.addonId;
    displayName = metadata.displayName;
    upstreamRev = metadata.rev;
  };

  meta = {
    description = "Arista Browser Extension Firefox build";
    homepage = "https://gerrit.corp.arista.io/plugins/gitiles/tools/arista-browser-extension";
    license = lib.licenses.mit;
    platforms = [ "aarch64-darwin" ];
  };
}
