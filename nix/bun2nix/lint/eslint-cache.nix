# Materialize the vendored eslint stack into a content-addressed store
# path that exposes a single `bin/eslint` already wired to the bundled
# flat config. Consumers (mkBundle in build-bun-binary.nix, the bundle
# step in build-zx-script.nix) just call:
#
#   ${eslintCache}/bin/eslint <entrypoint-paths>
#
# and don't need to know about node_modules layout or --config flags.
#
# Built once per (eslint, plugin, parser) version triple — bumps go
# through `nix run .#regen-lint-stack` (see regen.nix), which updates
# bun.lock and bun.nix; the cache rebuilds automatically.
{
  pkgs,
  bun,
  fetchBunDeps,
  bunNix,
  packageJson,
  bunLock,
  eslintConfig,
}:

let
  cache = fetchBunDeps { inherit bunNix; };

  installed = pkgs.stdenvNoCC.mkDerivation {
    pname = "bun-fork-lint-installed";
    version = "0.0.1";
    dontUnpack = true;

    nativeBuildInputs = [ bun ];

    buildPhase = ''
      runHook preBuild

      cp ${packageJson} package.json
      cp ${bunLock} bun.lock
      cp ${eslintConfig} eslint.config.js

      export BUN_INSTALL_CACHE_DIR=$(mktemp -d)
      cp -r ${cache}/share/bun-cache/. "$BUN_INSTALL_CACHE_DIR"
      bun install --frozen-lockfile --linker=isolated

      mkdir -p $out
      cp -r node_modules $out/node_modules
      cp eslint.config.js $out/eslint.config.js

      runHook postBuild
    '';

    dontInstall = true;
    dontFixup = true;
  };

in
pkgs.runCommand "bun-fork-lint"
  {
    nativeBuildInputs = [ pkgs.makeWrapper ];
  }
  ''
    mkdir -p $out/bin
    makeWrapper ${installed}/node_modules/.bin/eslint $out/bin/eslint \
      --add-flags "--config ${installed}/eslint.config.js" \
      --add-flags "--no-config-lookup"
  ''
