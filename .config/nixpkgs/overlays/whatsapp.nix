self: super: {
  whatsapp-for-mac = super.whatsapp-for-mac.overrideAttrs (o: rec {
    version = "2.25.24.76";
    src = super.fetchzip {
      extension = "zip";
      name = "WhatsApp.app";
      url = "https://web.whatsapp.com/desktop/mac_native/release/?version=${version}&extension=zip&configuration=Release&branch=relbranch";
      hash = "sha256-fzLV/u7TDVp/LWRTaztsX4YxyCZ++mXOKI2nyK7J8F8=";
    };
  });
}
