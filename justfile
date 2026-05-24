default: validate

build:
  bun bd

test *args:
  bun bd test {{args}}

fmt:
  nix fmt

validate: validate-flake validate-devshell

validate-flake:
  nix flake check

# Verify the devShell evaluates and builds without errors. Catches
# vendor-env / overlay breakage that `nix flake check` and the prod
# build can mask. No store-output usage --- just a build-check.
validate-devshell:
  nix build --no-link .#devShells.{{arch()}}-linux.default

clean:
  nix-store --gc

# Resolve SRI hashes for ///!dep directives in a zx script
update-zx-deps script:
  bun scripts/update-zx-deps.ts {{script}}

# Check that all ///!dep hashes are up to date (for CI)
check-zx-deps script:
  bun scripts/update-zx-deps.ts --check {{script}}

# Run bats end-to-end tests for nix builders (no sandbox: tests need nix daemon + network)
[group('test')]
test-bats *args:
  bats --no-sandbox zz-tests_bats/ {{args}}

# Compare cold-start time: ESM bundle vs bytecode CJS.
# Bytecode requires CJS (no top-level await), ESM supports TLA.
[group('explore')]
bench-startup:
  #!/usr/bin/env bash
  set -euo pipefail
  dir=$(mktemp -d)
  trap 'rm -rf "$dir"' EXIT
  echo 'console.log("hello");' > "$dir/entry.ts"
  bun build "$dir/entry.ts" --target=bun --format=esm --outdir="$dir/esm"
  bun build "$dir/entry.ts" --target=bun --bytecode --outdir="$dir/bytecode"
  nix run nixpkgs#hyperfine -- \
    --warmup 3 \
    --min-runs 50 \
    "bun $dir/esm/entry.js" \
    "bun $dir/bytecode/entry.js"
