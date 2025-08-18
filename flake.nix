{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    sdl_shadercross.url = "github:KamWithK/sdl_shadercross_flake";

    odinPatch = {
      url = "https://github.com/NixOS/nixpkgs/pull/431916.patch";
      flake = false;
    };
    slangPatch = {
      url = "https://github.com/NixOS/nixpkgs/pull/427622.patch";
      flake = false;
    };
  };

  outputs =
    {
      nixpkgs,
      odinPatch,
      slangPatch,
      sdl_shadercross,
      ...
    }:
    let
      forEachSystem =
        f:
        nixpkgs.lib.genAttrs nixpkgs.lib.systems.flakeExposed (
          system:
          f {
            pkgs = import nixpkgs {
              inherit system;
            };
          }
        );
    in
    {
      devShells = forEachSystem (
        { pkgs }:
        let
          patchedNixpkgs = pkgs.applyPatches {
            src = pkgs.path;
            patches = [
              odinPatch
              slangPatch
            ];
          };
          patchedPkgs = import patchedNixpkgs { inherit (pkgs) system; };
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
              xorg.libXcursor
              xorg.libXext
              xorg.libXfixes
              xorg.libXi
              xorg.libXrandr
            ];
        in
        {
          default = pkgs.mkShell {
            packages = with pkgs; [
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

              patchedPkgs.odin
              patchedPkgs.ols

              gdb
              clang-tools
              shader-slang

              sdl_shadercross.packages.${pkgs.system}.default
              vulkan-tools
              vulkan-validation-layers
              spirv-tools
              renderdoc

              wineWowPackages.stable

              sdl3
              sdl3-image
              sdl3-ttf
            ];

            LD_LIBRARY_PATH = libPath;
          };
        }
      );
    };
}
