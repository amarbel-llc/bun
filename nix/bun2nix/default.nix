# bun2nix library — vendored from nix-community/bun2nix, converted from
# flake-parts modules to plain callPackage functions.
#
# Usage:
#   let bun2nix = import ./nix/bun2nix { inherit pkgs bun cacheEntryCreator; };
#   in { inherit (bun2nix) buildBunBinary fetchBunDeps mkDerivation; }
#
# The cacheEntryCreator argument is a Zig binary from the upstream bun2nix
# flake (packages.${system}.cacheEntryCreator). It must be provided by the
# caller because we don't vendor the Zig/Rust source programs.
{
  pkgs,
  lib ? pkgs.lib,
  bun ? pkgs.bun,
  cacheEntryCreator,
}:

let
  # -- leaf components (no internal deps) --

  bun2nixNoOp = import ./bun2nix-no-op.nix { inherit pkgs; };

  extractPackage = import ./fetch-bun-deps/extract-package.nix { inherit pkgs lib; };

  cacheEntryCreator' = import ./fetch-bun-deps/cache-entry-creator.nix {
    inherit cacheEntryCreator;
  };

  patchedDependenciesToOverrides = import ./fetch-bun-deps/patched-dependencies-to-overrides.nix {
    inherit pkgs lib;
  };

  # -- mid-level components --

  overridePackage = import ./fetch-bun-deps/override-package.nix {
    inherit pkgs lib extractPackage;
  };

  buildPackage = import ./fetch-bun-deps/build-package.nix {
    inherit pkgs lib bun extractPackage;
    cacheEntryCreator = cacheEntryCreator';
  };

  hook = import ./hook.nix {
    inherit pkgs lib bun bun2nixNoOp;
  };

  # -- top-level API --

  fetchBunDeps = import ./fetch-bun-deps.nix {
    inherit pkgs lib buildPackage overridePackage patchedDependenciesToOverrides;
  };

  mkDerivation = import ./mk-derivation.nix {
    inherit pkgs lib hook;
  };

  writeBunApplication = import ./write-bun-application.nix {
    inherit pkgs lib bun mkDerivation;
  };

  writeBunScriptBin = import ./write-bun-script-bin.nix {
    inherit pkgs bun;
  };

  bunBinaryBuilders = import ./build-bun-binary.nix {
    inherit pkgs lib bun fetchBunDeps;
  };

  zxScriptBuilder = import ./build-zx-script.nix {
    inherit pkgs lib bun fetchBunDeps;
  };

in
{
  inherit (bunBinaryBuilders) buildBunBinary buildBunBinaries;
  inherit (zxScriptBuilder) buildZxScript;
  inherit
    fetchBunDeps
    hook
    mkDerivation
    writeBunApplication
    writeBunScriptBin
    ;
}
