{
  requireFile,
  metadata ? builtins.fromJSON (builtins.readFile ./metadata.json),
}:
if metadata.signedXpiHash == null
then null
else
  requireFile {
    name = "arista-browser-extension-${metadata.upstreamVersion}.xpi";
    hash = metadata.signedXpiHash;
    message = ''
      The signed Arista Browser Extension ${metadata.upstreamVersion} is not in the Nix store.
      Run `nix run .#update-arista-browser-extension` on the work Mac to build,
      sign, verify, and add it to the store.
    '';
  }
