self: super: {
  whatsapp-for-mac = super.whatsapp-for-mac.overrideAttrs (o: rec {
    version = "2.25.22.79";
    src = super.fetchzip {
      extension = "zip";
      name = "WhatsApp.app";
      url = "https://web.whatsapp.com/desktop/mac_native/release/?version=${version}&extension=zip&configuration=Release&branch=relbranch";
      hash = "sha256-LYjPMiXLD1U5ZNt/acBagrV2RS7U/OGMJ06mUFBluSQ=";
    };
  });
}
