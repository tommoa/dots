{pkgs, ...}: {
  home.packages = with pkgs;
    [
      clang
      clang-tools # Includes clangd language server
    ]
    # gdb on Linux, lldb on macOS (where gdb is not well supported)
    ++ (
      if pkgs.stdenv.isLinux
      then [gdb]
      else [lldb]
    );
}
