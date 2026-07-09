{
  description = "Obsidian embed checks";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/release-26.05";
    nvim-config = {
      url = "path:../../..";
      flake = false;
    };
  };

  outputs = {
    nvim-config,
    nixpkgs,
    ...
  }: let
    systems = [
      "x86_64-linux"
      "aarch64-darwin"
      "aarch64-linux"
    ];
    forAllSystems = f: nixpkgs.lib.genAttrs systems (system: f system);
  in {
    checks = forAllSystems (
      system: let
        pkgs = import nixpkgs {inherit system;};
        obsidian-nvim = pkgs.fetchFromGitHub {
          owner = "obsidian-nvim";
          repo = "obsidian.nvim";
          rev = "4bf07e502c4e35425a0bfc3438232a10971c1355";
          hash = "sha256-jSaAT7DCGsgzNJCd+ey3My2zqQ7kDcRm5ALDTOJKmJM=";
        };
        plenary-nvim = pkgs.fetchFromGitHub {
          owner = "nvim-lua";
          repo = "plenary.nvim";
          rev = "74b06c6c75e4eeb3108ec01852001636d85a932b";
          hash = "sha256-nkfETDkPiE+Kd2BWYZijgUp9bP8RgFwRmvqJz2BMuq4=";
        };
        treesitter = pkgs.vimPlugins.nvim-treesitter.withPlugins (p: [
          p.markdown
          p.markdown_inline
        ]);
      in {
        obsidian-embeds = pkgs.runCommand "obsidian-embeds-smoke" {
          nativeBuildInputs = [
            pkgs.neovim
            pkgs.ripgrep
          ];
          OBSIDIAN_EMBEDS_RTP = nixpkgs.lib.concatStringsSep ":" [
            "${obsidian-nvim}"
            "${plenary-nvim}"
            "${treesitter}"
          ];
        } ''
          export HOME="$TMPDIR/home"
          export XDG_CONFIG_HOME="$HOME/.config"
          export XDG_DATA_HOME="$TMPDIR/data"
          export XDG_STATE_HOME="$TMPDIR/state"
          mkdir -p "$HOME" "$XDG_CONFIG_HOME" "$XDG_DATA_HOME" "$XDG_STATE_HOME"

          cp -R ${nvim-config} "$HOME/.config/nvim"
          chmod -R u+w "$HOME/.config/nvim"

          nvim --headless -l "$XDG_CONFIG_HOME/nvim/lua/tom/obsidian_embeds/scripts/obsidian-embeds-state-smoke.lua"
          nvim --headless -l "$XDG_CONFIG_HOME/nvim/lua/tom/obsidian_embeds/scripts/obsidian-embeds-planner-smoke.lua"
          nvim --headless -l "$XDG_CONFIG_HOME/nvim/lua/tom/obsidian_embeds/scripts/obsidian-embeds-command-contract-smoke.lua"
          nvim --headless -l "$XDG_CONFIG_HOME/nvim/lua/tom/obsidian_embeds/scripts/obsidian-embeds-smoke.lua"
          nvim --headless -l "$XDG_CONFIG_HOME/nvim/lua/tom/obsidian_embeds/scripts/obsidian-embeds-dependencies-smoke.lua"
          nvim --headless -l "$XDG_CONFIG_HOME/nvim/lua/tom/obsidian_embeds/scripts/obsidian-embeds-workspace-smoke.lua"
          nvim --headless -l "$XDG_CONFIG_HOME/nvim/lua/tom/obsidian_embeds/scripts/obsidian-embeds-performance-smoke.lua"

          touch "$out"
        '';
      }
    );
  };
}
