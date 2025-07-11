{
  inputs = {
    flake-utils.url = "github:numtide/flake-utils";
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    zig.url = "github:mitchellh/zig-overlay";
  };

  outputs =
    inputs:
    inputs.flake-utils.lib.eachDefaultSystem (
      system:
      let
        pkgs = (
          import (inputs.nixpkgs) {
            inherit system;
            systems = builtins.attrNames inputs.zig.packages;
          }
        );
        zig = inputs.zig.packages.${pkgs.system}.default;
        libPath =
          with pkgs;
          lib.makeLibraryPath [
            libGL
            vulkan-headers
            vulkan-loader

            libxkbcommon
            wayland
            libdecor

            xorg.libX11
            xorg.libXScrnSaver
            xorg.libXcursor
            xorg.libXext
            xorg.libXfixes
            xorg.libXi
            xorg.libXrandr
          ];
      in
      {
        devShell = pkgs.mkShell {
          packages = with pkgs; [
            zig
            zls
            gdb
            clang-tools

            shader-slang
            vulkan-tools
            vulkan-validation-layers
            spirv-tools
            renderdoc

            wineWowPackages.stable
          ];
          LD_LIBRARY_PATH = libPath;
        };
      }
    );
}
