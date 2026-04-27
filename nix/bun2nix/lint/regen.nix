# Regenerate nix/bun2nix/lint/{bun.lock,bun.nix} from package.json.
#
# Usage (impure, run from devshell — needs network):
#   nix run .#regen-lint-stack
#
# This is the impure half of the bootstrap problem: `bun install` must
# resolve semver ranges against the npm registry, which Nix derivations
# cannot do without a fixed-output hash. So we run `bun install` outside
# the sandbox via a flake app, and commit the resulting lockfile + the
# bun2nix-generated bun.nix.
#
# The drift guard in check.nix (sandboxed, pure) verifies bun.nix is up
# to date relative to bun.lock. It does not verify bun.lock matches
# package.json — same gap Cargo's `cargo check` has, fix is "rerun this
# script after editing package.json".
#
# See:
#   - amarbel-llc/bun#7 (the lint pass this stack feeds)
#   - docs/decisions/0001-vendor-eslint-stack-for-buildbunbinary-lint.md
{
  pkgs,
  bun,
  bun2nix,
}:

pkgs.writeShellApplication {
  name = "regen-lint-stack";
  runtimeInputs = [
    bun
    bun2nix
    pkgs.coreutils
  ];
  text = ''
    set -euo pipefail

    # Resolve the lint dir relative to the flake root so this works
    # regardless of where the user invokes `nix run` from.
    if [ -z "''${LINT_DIR:-}" ]; then
      script_dir="$(cd "$(dirname "''${BASH_SOURCE[0]:-$0}")" && pwd)"
      # When run via `nix run`, BASH_SOURCE points into /nix/store;
      # fall back to PWD-based discovery.
      if [[ "$script_dir" == /nix/store/* ]]; then
        if [ -f "$PWD/nix/bun2nix/lint/package.json" ]; then
          LINT_DIR="$PWD/nix/bun2nix/lint"
        elif [ -f "$PWD/package.json" ] && grep -q '"name": "bun-fork-lint"' "$PWD/package.json"; then
          LINT_DIR="$PWD"
        else
          echo "regen-lint-stack: cannot find nix/bun2nix/lint/. Run from the repo root or set LINT_DIR." >&2
          exit 2
        fi
      else
        LINT_DIR="$script_dir"
      fi
    fi

    echo "regen-lint-stack: working in $LINT_DIR"
    cd "$LINT_DIR"

    if [ ! -f package.json ]; then
      echo "regen-lint-stack: no package.json in $LINT_DIR" >&2
      exit 2
    fi

    # 1. Refresh bun.lock against the npm registry (impure — needs network).
    #    --linker=isolated mirrors what the build-time install does.
    echo "regen-lint-stack: running bun install to refresh bun.lock"
    bun install --linker=isolated

    # 2. Convert bun.lock to bun.nix (pure — bun2nix doesn't touch the network).
    echo "regen-lint-stack: running bun2nix to refresh bun.nix"
    bun2nix --lock-file=./bun.lock --output-file=./bun.nix

    # 3. Drop node_modules — it's a side-effect of step 1 and not committed.
    rm -rf node_modules

    echo "regen-lint-stack: done. Review and commit bun.lock + bun.nix."
  '';
}
