self: super: {
  whatsapp-for-mac = super.whatsapp-for-mac.overrideAttrs (o: rec {
    version = "2.25.28.17";
    src = super.fetchzip {
      extension = "zip";
      name = "WhatsApp.app";
      url = "https://web.whatsapp.com/desktop/mac_native/release/?version=${version}&extension=zip&configuration=Release";
      hash = "sha256-Mc8+d8Kb58kfJ61Qy38mgItwtNkz1bdKhf6J09bawQ0=";
    };
  });
}
