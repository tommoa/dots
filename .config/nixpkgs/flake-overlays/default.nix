inputs: self: super: {
  opencode =
    inputs.opencode.packages.${super.stdenv.hostPlatform.system}.default.overrideAttrs
    (old: {
      preBuild =
        (old.preBuild or "")
        + ''
          substituteInPlace packages/opencode/src/cli/cmd/generate.ts \
            --replace-fail 'const prettier = await import("prettier")' 'const prettier: any = { format: async (s: string) => s }' \
            --replace-fail 'const babel = await import("prettier/plugins/babel")' 'const babel = {}' \
            --replace-fail 'const estree = await import("prettier/plugins/estree")' 'const estree = {}'
        '';
    });

  opencode-desktop =
    inputs.opencode.packages.${super.stdenv.hostPlatform.system}.default.overrideAttrs
    (
      finalAttrs: old: {
        pname = "opencode-desktop";

        nativeBuildInputs =
          (old.nativeBuildInputs or [])
          ++ [
            super.makeWrapper
            super.nodejs
          ];

        runtimePath = super.lib.makeBinPath [super.ripgrep];

        electronBuilderFlags = [
          "--config"
          "electron-builder.config.ts"
          "--config.extraMetadata.version=${old.version}"
          "--config.electronVersion=${super.electron.version}"
        ];

        desktopItem = super.makeDesktopItem {
          name = "opencode-desktop";
          desktopName = "OpenCode";
          comment = "OpenCode Desktop App";
          exec = "opencode-desktop";
          icon = "opencode-desktop";
          categories = ["Development"];
          startupWMClass = "OpenCode";
        };

        darwinAfterExtract = super.writeText "opencode-desktop-after-extract.cjs" ''
          const fs = require("node:fs/promises")
          const path = require("node:path")

          async function chmodWritable(file) {
            const stat = await fs.lstat(file)
            await fs.chmod(file, stat.mode | 0o200)
            if (!stat.isDirectory()) return
            await Promise.all((await fs.readdir(file)).map((entry) => chmodWritable(path.join(file, entry))))
          }

          module.exports = async (context) => {
            if (context.electronPlatformName !== "darwin") return
            await chmodWritable(path.join(context.appOutDir, "Electron.app"))
          }
        '';

        env =
          (old.env or {})
          // {
            OPENCODE_CHANNEL = "prod";
            OPENCODE_DISABLE_UPDATER = "true";
            OPENCODE_VERSION = old.version;
          };

        preBuild = ''
          substituteInPlace packages/opencode/src/cli/cmd/generate.ts \
            --replace-fail 'const prettier = await import("prettier")' 'const prettier: any = { format: async (s: string) => s }' \
            --replace-fail 'const babel = await import("prettier/plugins/babel")' 'const babel = {}' \
            --replace-fail 'const estree = await import("prettier/plugins/estree")' 'const estree = {}'
        '';

        buildPhase =
          ''
            runHook preBuild

            cd packages/desktop
            bun ./scripts/prebuild.ts
            bun run build
          ''
          + super.lib.optionalString super.stdenv.hostPlatform.isDarwin ''
            bunx electron-builder --mac dir ${
              super.lib.escapeShellArgs (
                finalAttrs.electronBuilderFlags
                ++ [
                  "--config.electronDist=${super.electron}/Applications"
                  "--config.afterExtract=${finalAttrs.darwinAfterExtract}"
                  "--config.mac.identity=null"
                  "--config.mac.hardenedRuntime=false"
                  "--config.mac.notarize=false"
                ]
              )
            }
          ''
          + super.lib.optionalString super.stdenv.hostPlatform.isLinux ''
            bunx electron-builder --linux dir ${
              super.lib.escapeShellArgs (
                finalAttrs.electronBuilderFlags
                ++ [
                  "--config.electronDist=${super.electron}/libexec/electron"
                  "--config.linux.executableName=opencode"
                ]
              )
            }
          ''
          + ''

            runHook postBuild
          '';

        installPhase =
          ''
            runHook preInstall

          ''
          + super.lib.optionalString super.stdenv.hostPlatform.isDarwin ''
            mkdir -p $out/Applications $out/bin
            cp -R dist/mac*/OpenCode.app $out/Applications/
            wrapProgram $out/Applications/OpenCode.app/Contents/MacOS/OpenCode \
              --prefix PATH : ${finalAttrs.runtimePath}
            makeWrapper $out/Applications/OpenCode.app/Contents/MacOS/OpenCode $out/bin/opencode-desktop
          ''
          + super.lib.optionalString super.stdenv.hostPlatform.isLinux ''
            mkdir -p $out/share/opencode-desktop $out/bin
            cp -R dist/linux-unpacked/. $out/share/opencode-desktop/
            makeWrapper $out/share/opencode-desktop/opencode $out/bin/opencode-desktop \
              --prefix PATH : ${finalAttrs.runtimePath}

            install -Dm644 resources/icons/32x32.png $out/share/icons/hicolor/32x32/apps/opencode-desktop.png
            install -Dm644 resources/icons/64x64.png $out/share/icons/hicolor/64x64/apps/opencode-desktop.png
            install -Dm644 resources/icons/128x128.png $out/share/icons/hicolor/128x128/apps/opencode-desktop.png
            install -Dm644 resources/icons/128x128@2x.png $out/share/icons/hicolor/256x256/apps/opencode-desktop.png
            cp -R ${finalAttrs.desktopItem}/share/applications $out/share/
          ''
          + ''

            runHook postInstall
          '';

        doInstallCheck = false;
        postInstall = "";
        postFixup = "";

        meta = {
          description = "OpenCode Desktop App";
          homepage = "https://opencode.ai";
          license = super.lib.licenses.mit;
          platforms = [
            "aarch64-linux"
            "aarch64-darwin"
            "x86_64-linux"
            "x86_64-darwin"
          ];
          mainProgram = "opencode-desktop";
        };
      }
    );
}
