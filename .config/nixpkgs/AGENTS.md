# Agent Guidelines for Nix Configuration Repository

## Build/Update Commands
- **Update system**: `./update-nix [system|home|both] [config-name]` (auto-detects: apollo, james)
- **Validate flake**: `nix flake check` (validates flake syntax and builds)
- **Format code**: `nix fmt` (uses `nixfmt-rfc-style`)
- **Build home config**: `nix build .#homeConfigurations."toma@work".activationPackage`
- **Build darwin config**: `nix build .#darwinConfigurations.apollo.system`
- **Build nixos config**: `nix build .#nixosConfigurations.james.config.system.build.toplevel`
- **Dry run**: Add `--dry-run` to darwin-rebuild/nixos-rebuild commands
- **List configs**: `nix eval .#homeConfigurations --apply builtins.attrNames`

## Code Style Guidelines
- **File structure**: Use modular approach with profiles in `modules/{darwin,nixos,home-manager}/profiles/`
- **Imports**: Place at top of file, use relative paths (`./development/nix.nix`), empty line after
- **Formatting**: 2-space indentation, no trailing whitespace; run `nix fmt` before committing
- **Comments**: Use `#` for explanatory comments, avoid inline comments
- **Naming**: Use kebab-case for files (`base.nix`), camelCase for attributes
- **Package lists**: Use `with pkgs;` pattern, alphabetical ordering, group by category
- **Conditionals**: Use `pkgs.stdenv.isLinux`/`pkgs.stdenv.isDarwin` for platform detection
- **Helper functions**: Define in `let...in` blocks with descriptive names (see `mkHomeConfig` in flake.nix)
- **Attributes**: Use explicit attribute sets, avoid unnecessary nesting

## Configuration Structure
- **Hosts**: `hosts/{apollo,james}.nix` for system-specific configs
- **Profiles**: Reusable modules in `modules/*/profiles/` (base, desktop, development, server)
- **Common**: Shared modules in `modules/common/` (base, fonts, nix)
- **Overlays**: Custom packages in `overlays/` directory, compose with `//` operator in `overlays/default.nix`
- **Secrets**: Managed via agenix in `secrets/` directory; decrypted secrets defined in profile modules
- **Flake outputs**: homeConfigurations, darwinConfigurations, nixosConfigurations

## Error Handling
- Always run `nix flake check` and `nix fmt .` before committing
- Test configurations with `nix build` before switching
- Use `nix eval` to check attribute existence before referencing
