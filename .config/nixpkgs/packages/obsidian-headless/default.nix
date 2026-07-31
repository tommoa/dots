{
  buildNpmPackage,
  lib,
  makeWrapper,
  nodejs_24,
  python3,
  stdenv,
}:
buildNpmPackage {
  pname = "obsidian-headless";
  version = "0.0.14";

  src = ./.;
  npmDepsHash = "sha256-3Abu47/kLBUTynJcUNj03OWReCw0U1W6FfhWA+c5bGY=";

  dontNpmBuild = true;

  nativeBuildInputs = [
    makeWrapper
    python3
  ];

  installPhase = ''
    runHook preInstall

    mkdir -p "$out/lib/obsidian-headless" "$out/bin"
    cp -R node_modules "$out/lib/obsidian-headless/"
    makeWrapper ${nodejs_24}/bin/node "$out/bin/ob" \
      --add-flags "$out/lib/obsidian-headless/node_modules/obsidian-headless/cli.js"

    runHook postInstall
  '';

  meta = {
    description = "Headless client for Obsidian Sync";
    homepage = "https://obsidian.md/help/sync/headless";
    license = lib.licenses.unfree;
    mainProgram = "ob";
    platforms = [
      "aarch64-darwin"
      "x86_64-darwin"
      "x86_64-linux"
    ];
  };
}
