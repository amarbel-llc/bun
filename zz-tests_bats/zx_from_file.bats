#!/usr/bin/env bats

setup() {
  load "$(dirname "$BATS_TEST_FILE")/common.bash"
}

function nix_build_test_zx_from_file_succeeds { # @test
  run nix build .#test-zx-from-file --no-link
  assert_success
}

function nix_run_test_zx_from_file_produces_expected_output { # @test
  run nix run .#test-zx-from-file
  assert_success
  assert_output --partial "zx + chalk: hello from file-based deps"
}

function update_zx_deps_check_passes_with_valid_hashes { # @test
  run bun scripts/update-zx-deps.ts --check test/nix/zx-from-file/index.ts
  assert_success
  assert_output --partial "All hashes up to date"
}

function update_zx_deps_resolves_missing_hashes { # @test
  local tmp
  tmp=$(mktemp -d)

  cp test/nix/zx-from-file/index.ts "$tmp/index.ts"

  # Strip hashes from directives
  sed -i.bak 's|///!dep \([^ ]*\) .*|///!dep \1|' "$tmp/index.ts"

  # --check should fail with missing hashes
  run bun scripts/update-zx-deps.ts --check "$tmp/index.ts"
  assert_failure

  # Resolve hashes
  run bun scripts/update-zx-deps.ts "$tmp/index.ts"
  assert_success
  assert_output --partial "Updated 2 hash(es)"

  # Idempotent: --check should now pass
  run bun scripts/update-zx-deps.ts --check "$tmp/index.ts"
  assert_success

  rm -rf "$tmp"
}

function missing_hash_fails_nix_eval_with_actionable_error { # @test
  local tmp
  tmp=$(mktemp -d /tmp/bats-zx-eval.XXXXXX)

  cp test/nix/zx-from-file/index.ts "$tmp/index.ts"
  sed -i.bak 's|///!dep \([^ ]*\) .*|///!dep \1|' "$tmp/index.ts"

  local system
  system=$(nix eval --impure --expr builtins.currentSystem --raw)

  git -C "$tmp" init -q
  cat > "$tmp/flake.nix" <<EOF
{
  inputs.bun.url = "path:$(pwd)";
  inputs.nixpkgs.follows = "bun/nixpkgs";
  outputs = { self, bun, nixpkgs }:
    let
      pkgs = import nixpkgs { system = "$system"; };
      bunLib = bun.lib.mkBunLib { inherit pkgs; };
    in {
      packages.$system.default = bunLib.buildZxScriptFromFile {
        pname = "test-missing-hash";
        script = ./index.ts;
      };
    };
}
EOF
  git -C "$tmp" add -A

  run nix build "$tmp#packages.$system.default" --no-link 2>&1
  assert_failure
  assert_output --partial "has no SRI hash"
  assert_output --partial "update-zx-deps"

  rm -rf "$tmp"
}
