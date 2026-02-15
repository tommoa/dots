self: super: {
  # Override aerc to patch vaxis with kitty graphics support in the
  # embedded terminal widget. This allows w3m's kitty image protocol
  # output to be decoded and re-rendered by vaxis, enabling inline
  # images in HTML email filters on terminals that support kitty
  # graphics (like ghostty).
  aerc = super.aerc.overrideAttrs (old: {
    # Switch from proxyVendor to vendored mode so we can patch the
    # vaxis source in vendor/. The vendorHash changes because the
    # output format differs (vendor/ tree vs module cache).
    proxyVendor = false;
    vendorHash = "sha256-Vri4Pz2mKkLGQPAaES9SMnzBzkWRFlGUa3524ZSI1lk=";

    postConfigure =
      (old.postConfigure or "")
      + ''
        # Make vendored vaxis writable for patching
        chmod -R u+w vendor/git.sr.ht/~rockorager/vaxis

        # Patch 1: kitty graphics support in embedded terminal widget
        patch -p1 -d vendor/git.sr.ht/~rockorager/vaxis < ${./vaxis-kitty-graphics.patch}

        # Patch 2: tmux DCS passthrough for kitty graphics
        patch -p1 -d vendor/git.sr.ht/~rockorager/vaxis < ${./vaxis-tmux-passthrough.patch}
      '';
  });
}
