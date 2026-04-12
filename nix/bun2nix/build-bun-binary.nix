# buildBunBinary { pname, version, src, entrypoint, bunNix, ... }
#
# Produces $out/bin/$pname — a shell wrapper that execs bun from the
# nix store with a pre-built bytecode bundle. The bun runtime is a
# shared store path, not embedded in the output.
#
# Two derivations:
#   1. bundle: runs `bun build --target=bun --format=esm` (heavy, cached)
#   2. wrapper: writeShellScriptBin (trivial, references store bun + bundle)
#
# Uses ESM format (not --bytecode) to support top-level await, which is
# common in script-style entrypoints. Bytecode forces CJS output format
# which rejects top-level await. See amarbel-llc/bun#2.
#
# The `bun` argument is overridable — when a future bun-minimal exists,
# consumers just pass it.
{ pkgs, lib, bun, fetchBunDeps }:

{
  pname,
  version,
  src,
  entrypoint ? "index.ts",
  bunNix ? null,
  bunBuildFlags ? [ ],
  runtimeInputs ? [ ],
  runtimeEnv ? { },
  bunfigPath ? null,
  npmrcPath ? null,
  overrides ? { },
  ...
}:

let
  hasDeps = bunNix != null;

  bunDeps = lib.optionalAttrs hasDeps {
    cache = fetchBunDeps {
      inherit bunNix bunfigPath npmrcPath overrides;
    };
  };

  bundle = pkgs.stdenvNoCC.mkDerivation {
    pname = "${pname}-bundle";
    inherit version src;

    nativeBuildInputs = [ bun ];

    buildPhase = ''
      runHook preBuild

      ${lib.optionalString hasDeps ''
        export BUN_INSTALL_CACHE_DIR=$(mktemp -d)
        cp -r ${bunDeps.cache}/share/bun-cache/. "$BUN_INSTALL_CACHE_DIR"
        bun install --frozen-lockfile --linker=isolated
      ''}

      mkdir -p $out
      bun build ${lib.escapeShellArg entrypoint} \
        --target=bun \
        --format=esm \
        --outdir=$out \
        ${lib.escapeShellArgs bunBuildFlags}

      runHook postBuild
    '';

    dontInstall = true;
    dontFixup = true;
  };

  envExports = lib.concatStringsSep "\n" (
    lib.mapAttrsToList (k: v: "export ${k}=${lib.escapeShellArg v}") runtimeEnv
  );

  pathSetup = lib.optionalString (runtimeInputs != [ ]) ''
    export PATH="${lib.makeBinPath runtimeInputs}:$PATH"
  '';

in
pkgs.writeShellScriptBin pname ''
  ${envExports}
  ${pathSetup}
  exec ${bun}/bin/bun ${bundle}/${lib.replaceStrings [".ts" ".tsx" ".mts" ".cts"] [".js" ".js" ".js" ".js"] (builtins.baseNameOf entrypoint)} "$@"
''
