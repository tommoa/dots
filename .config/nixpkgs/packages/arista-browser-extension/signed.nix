{
  requireFile,
  aristaMetadata ? builtins.fromJSON (builtins.readFile ./metadata.json),
}:
if aristaMetadata.signedXpiHash == null
then null
else
  requireFile {
    name = "arista-browser-extension-${aristaMetadata.upstreamVersion}.xpi";
    hash = aristaMetadata.signedXpiHash;
    message = ''
      The signed Arista Browser Extension ${aristaMetadata.upstreamVersion} is not in the Nix store.
      Run `bash packages/arista-browser-extension/update.sh` from the flake directory on the work Mac to build,
      sign, verify, and add it to the store.
    '';
  }
