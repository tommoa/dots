self: super: {
  whatsapp-for-mac = super.whatsapp-for-mac.overrideAttrs (o: rec {
    version = "2.25.31.11";
    src = super.fetchzip {
      extension = "zip";
      name = "WhatsApp.app";
      url = "https://web.whatsapp.com/desktop/mac_native/release/?version=${version}&extension=zip&configuration=Release";
      hash = "sha256-tRQwANJ+lm68ch48vk7JCJMNxMeuSGC65sUdu+/kEnY=";
    };
  });
}
